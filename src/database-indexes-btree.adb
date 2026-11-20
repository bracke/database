with Ada.Containers;
with Ada.Containers.Ordered_Sets;
with Database.Indexes.BTree.Nodes;

package body Database.Indexes.BTree is
   use type Ada.Containers.Count_Type;
   use Database.Storage.Pages;
   use Database.Indexes.BTree.Nodes;

   package Page_Sets is new Ada.Containers.Ordered_Sets (Page_Id);

   function Not_Built return Database.Status.Result is
     (Database.Status.Failure (Database.Status.Not_Found, "index is not built"));

   function Too_Deep return Database.Status.Result is
     (Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree path exceeds the page count"));

   function Within_Bound
     (Key   : Database.Values.Value;
      Bound : Range_Bound;
      Low   : Boolean) return Boolean is
      Order : Database.Indexes.Ordering;
      R     : Database.Status.Result;
   begin
      if Bound.Kind = Unbounded then
         return True;
      end if;
      R := Database.Indexes.Compare (Key, Bound.Key, Order);
      if not Database.Status.Is_Ok (R) then
         return False;
      end if;
      if Low then
         return Order = Database.Indexes.Greater
           or else (Bound.Kind = Inclusive and then Order = Database.Indexes.Equal);
      else
         return Order = Database.Indexes.Less
           or else (Bound.Kind = Inclusive and then Order = Database.Indexes.Equal);
      end if;
   end Within_Bound;

   --  How a descent chooses a child: the subtree that may hold the first entry with a key, or the subtree that holds
   --  the place of one (key, reference) entry.
   type Target_Kind is (First_With_Key, Exact_Entry);

   --  Descend from Root to the leaf for a target, recording the internal nodes passed, root first.
   function Leaf_For
     (F      : in out Database.Storage.File_IO.File_Handle;
      Root   : Page_Id;
      Target : Target_Kind;
      Key    : Database.Values.Value;
      Ref    : Database.Indexes.Row_Reference;
      Leaf   : out Node;
      Path   : out Page_Id_Vectors.Vector) return Database.Status.Result
   is
      Limit : constant Natural := Database.Storage.File_IO.Page_Count (F);
      R     : Database.Status.Result := Load (F, Root, Leaf);
   begin
      Path.Clear;
      while Database.Status.Is_Ok (R) and then not Leaf.Leaf loop
         if Natural (Path.Length) > Limit then
            return Too_Deep;
         end if;
         Path.Append (Leaf.Id);
         declare
            Child : Page_Id := Leaf.First;
            Order : Database.Indexes.Ordering;
         begin
            for Separator of Leaf.Items loop
               if Target = First_With_Key then
                  R := Database.Indexes.Compare (Separator.Key, Key, Order);
                  exit when not Database.Status.Is_Ok (R) or else Order /= Database.Indexes.Less;
               else
                  R := Compare (Separator.Key, Separator.Ref, Key, Ref, Order);
                  exit when not Database.Status.Is_Ok (R) or else Order = Database.Indexes.Greater;
               end if;
               Child := Separator.Child;
            end loop;
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            R := Load (F, Child, Leaf);
         end;
      end loop;
      return R;
   end Leaf_For;

   --  Index of the first entry of N that is not below (Key, Ref), and whether it equals it.
   function Position_Of
     (N     : Node;
      Key   : Database.Values.Value;
      Ref   : Database.Indexes.Row_Reference;
      Found : out Boolean;
      R     : out Database.Status.Result) return Natural
   is
      Order : Database.Indexes.Ordering;
   begin
      Found := False;
      R := Database.Status.Success;
      for I in 0 .. Natural (N.Items.Length) - 1 loop
         R := Compare (N.Items (I).Key, N.Items (I).Ref, Key, Ref, Order);
         if not Database.Status.Is_Ok (R) then
            return I;
         elsif Order /= Database.Indexes.Less then
            Found := Order = Database.Indexes.Equal;
            return I;
         end if;
      end loop;
      return Natural (N.Items.Length);
   end Position_Of;

   function Allocate
     (F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Leaf      : Boolean;
      Id        : out Page_Id) return Database.Status.Result
   is
      Page : Database.Storage.Pages.Page;
      R    : constant Database.Status.Result := Database.Storage.Free_List.Allocate
        (Allocator, F, (if Leaf then BTree_Leaf_Page else BTree_Internal_Page), Page);
   begin
      Id := (if Database.Status.Is_Ok (R) then Get_Id (Page) else Invalid_Page_Id);
      return R;
   end Allocate;

   --  The number of leading entries of N to keep when it splits: about half of its encoded bytes, at least one entry
   --  on each side.
   function Split_Point (N : Node) return Positive is
      Total, Running : Natural := 0;
   begin
      for Entry_Item of N.Items loop
         Total := Total + Item_Size (N, Entry_Item);
      end loop;
      for I in 0 .. Natural (N.Items.Length) - 1 loop
         Running := Running + Item_Size (N, N.Items (I));
         if Running >= Total / 2 then
            return Positive'Max (1, Positive'Min (I + (if N.Leaf then 1 else 0), Natural (N.Items.Length) - 1));
         end if;
      end loop;
      return Natural (N.Items.Length) - 1;
   end Split_Point;

   function Slice (Items : Item_Vectors.Vector; First, Last : Integer) return Item_Vectors.Vector is
      Result : Item_Vectors.Vector;
   begin
      for I in First .. Last loop
         Result.Append (Items (I));
      end loop;
      return Result;
   end Slice;

   --  Write N back after a change; when it no longer fits a page, split it and add the separator to its parent,
   --  splitting upward as needed. The root keeps its page: when it splits, its halves move to two new pages.
   function Write_Back
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      N         : in out Node;
      Path      : in out Page_Id_Vectors.Vector) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      loop
         if Fits (N) then
            return Store (Tx, F, N);
         end if;
         declare
            M         : constant Positive := Split_Point (N);
            Last      : constant Natural := Natural (N.Items.Length) - 1;
            Separator : Item := N.Items (M);
            Left      : Node := (Id => N.Id, Leaf => N.Leaf, First => N.First, Next => N.Next, Items => <>);
            Right     : Node := (Leaf => N.Leaf, others => <>);
         begin
            --  A leaf's separator copies its right half's first entry; an internal separator moves up, and its child
            --  becomes the right half's first child.
            Left.Items := Slice (N.Items, 0, M - 1);
            Right.Items := Slice (N.Items, (if N.Leaf then M else M + 1), Last);
            Right.First := (if N.Leaf then Invalid_Page_Id else Separator.Child);
            R := Allocate (F, Allocator, N.Leaf, Right.Id);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Separator.Child := Right.Id;
            if N.Leaf then
               Right.Next := N.Next;
               Left.Next := Right.Id;
            end if;
            if Path.Is_Empty then
               --  The root splits: its left half also moves to a new page, and the root becomes their parent.
               R := Allocate (F, Allocator, N.Leaf, Left.Id);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               R := Store (Tx, F, Left);
               if Database.Status.Is_Ok (R) then
                  R := Store (Tx, F, Right);
               end if;
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               N := (Id => N.Id, Leaf => False, First => Left.Id, Next => Invalid_Page_Id, Items => <>);
               N.Items.Append (Separator);
               return Store (Tx, F, N);
            end if;
            R := Store (Tx, F, Left);
            if Database.Status.Is_Ok (R) then
               R := Store (Tx, F, Right);
            end if;
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            R := Load (F, Path.Last_Element, N);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Path.Delete_Last;
            declare
               Found    : Boolean;
               Position : constant Natural := Position_Of (N, Separator.Key, Separator.Ref, Found, R);
            begin
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               N.Items.Insert (Position, Separator);
            end;
         end;
      end loop;
   end Write_Back;

   --  Add one (Key, Ref) entry; an entry that is already present is left as it is.
   function Add
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result
   is
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      Found : Boolean;
      R     : Database.Status.Result;
   begin
      if Key_Size (Key) > Max_Key_Bytes then
         return Database.Status.Failure (Database.Status.Row_Too_Large, "index key is too large");
      end if;
      R := Leaf_For (F, Root, Exact_Entry, Key, Ref, Leaf, Path);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      declare
         Position : constant Natural := Position_Of (Leaf, Key, Ref, Found, R);
      begin
         if not Database.Status.Is_Ok (R) or else Found then
            return R;
         end if;
         Leaf.Items.Insert (Position, Item'(Key => Key, Ref => Ref, Child => Invalid_Page_Id));
      end;
      return Write_Back (Tx, F, Allocator, Leaf, Path);
   end Add;

   function Create
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : out Database.Storage.Pages.Page_Id) return Database.Status.Result is
      R : constant Database.Status.Result := Allocate (F, Allocator, True, Root);
   begin
      if not Database.Status.Is_Ok (R) then
         Root := Invalid_Page_Id;
         return R;
      end if;
      return Reset (Tx, F, Root);
   end Create;

   function Reset
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result
   is
   begin
      return Store (Tx, F, (Id => Root, Leaf => True, others => <>));
   end Reset;

   function Is_Built
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Boolean is (Nodes.Is_Built (F, Root));

   function Is_Unwritten
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Boolean
   is
      Page : Database.Storage.Pages.Page;
   begin
      return Root /= Invalid_Page_Id
        and then Database.Status.Is_Ok (Database.Storage.File_IO.Read_Page (F, Root, BTree_Leaf_Page, Page))
        and then Used (Page) = 0;
   end Is_Unwritten;

   --  Visit the references of every entry within Low .. High in ascending order, until Process asks to stop.
   generic
      with procedure Process (Ref : Database.Indexes.Row_Reference; Stop : out Boolean);
   procedure Scan_Range_Generic
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Page_Id;
      Low  : Range_Bound;
      High : Range_Bound;
      R    : out Database.Status.Result);

   procedure Scan_Range_Generic
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Page_Id;
      Low  : Range_Bound;
      High : Range_Bound;
      R    : out Database.Status.Result)
   is
      Limit : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      Steps : Natural := 0;
      Stop  : Boolean := False;
   begin
      if not Is_Built (F, Root) then
         R := Not_Built;
         return;
      end if;
      if Low.Kind = Unbounded then
         R := Load (F, Root, Leaf);
         while Database.Status.Is_Ok (R) and then not Leaf.Leaf and then Steps <= Limit loop
            R := Load (F, Leaf.First, Leaf);
            Steps := Steps + 1;
         end loop;
      else
         R := Leaf_For (F, Root, First_With_Key, Low.Key, Database.Indexes.Invalid_Row_Reference, Leaf, Path);
      end if;
      loop
         exit when not Database.Status.Is_Ok (R);
         if Steps > Limit then
            R := Too_Deep;
            return;
         end if;
         for Entry_Item of Leaf.Items loop
            if not Within_Bound (Entry_Item.Key, High, False) then
               return;
            end if;
            if Within_Bound (Entry_Item.Key, Low, True) then
               Process (Entry_Item.Ref, Stop);
               if Stop then
                  return;
               end if;
            end if;
         end loop;
         exit when Leaf.Next = Invalid_Page_Id;
         R := Load (F, Leaf.Next, Leaf);
         Steps := Steps + 1;
      end loop;
   end Scan_Range_Generic;

   function Find
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : out Database.Indexes.Row_Reference) return Database.Status.Result
   is
      Found : Boolean := False;

      procedure Take (Candidate : Database.Indexes.Row_Reference; Stop : out Boolean) is
      begin
         Ref := Candidate;
         Found := True;
         Stop := True;
      end Take;

      Bound : constant Range_Bound := (Kind => Inclusive, Key => Key);
      R     : Database.Status.Result;

      procedure Scan is new Scan_Range_Generic (Take);
   begin
      Ref := Database.Indexes.Invalid_Row_Reference;
      Scan (F, Root, Bound, Bound, R);
      if not Database.Status.Is_Ok (R) then
         return R;
      elsif Found then
         return Database.Status.Success;
      end if;
      return Database.Status.Failure (Database.Status.Key_Not_Found, "index key not found");
   end Find;


   function Insert
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result is
      Existing : Database.Indexes.Row_Reference;
      R        : Database.Status.Result;
   begin
      if Root = Invalid_Page_Id then
         R := Create (Tx, F, Allocator, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      elsif not Is_Built (F, Root) then
         return Database.Status.Success;
      end if;
      R := Find (F, Root, Key, Existing);
      if Database.Status.Is_Ok (R) then
         return Database.Status.Failure (Database.Status.Duplicate_Key, "duplicate index key");
      elsif R.Code /= Database.Status.Key_Not_Found then
         return R;
      end if;
      return Add (Tx, F, Allocator, Root, Key, Ref);
   end Insert;

   function Insert_Duplicate
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if Root = Invalid_Page_Id then
         R := Create (Tx, F, Allocator, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      elsif not Is_Built (F, Root) then
         return Database.Status.Success;
      end if;
      return Add (Tx, F, Allocator, Root, Key, Ref);
   end Insert_Duplicate;

   function Remove_Entry
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result is
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      Found : Boolean;
      R     : Database.Status.Result;
   begin
      if not Is_Built (F, Root) then
         return Database.Status.Success;
      end if;
      R := Leaf_For (F, Root, Exact_Entry, Key, Ref, Leaf, Path);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      declare
         Position : constant Natural := Position_Of (Leaf, Key, Ref, Found, R);
      begin
         if not Database.Status.Is_Ok (R) or else not Found then
            return R;
         end if;
         Leaf.Items.Delete (Position);
      end;
      return Store (Tx, F, Leaf);
   end Remove_Entry;

   function Remove
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value) return Database.Status.Result is
      Limit : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      R     : Database.Status.Result;
      Steps : Natural := 0;
   begin
      if not Is_Built (F, Root) then
         return Database.Status.Success;
      end if;
      R := Leaf_For (F, Root, First_With_Key, Key, Database.Indexes.Invalid_Row_Reference, Leaf, Path);
      while Database.Status.Is_Ok (R) loop
         declare
            Changed : Boolean := False;
            Beyond  : Boolean := False;
            Order   : Database.Indexes.Ordering;
            I       : Natural := 0;
         begin
            while I < Natural (Leaf.Items.Length) loop
               R := Database.Indexes.Compare (Leaf.Items (I).Key, Key, Order);
               exit when not Database.Status.Is_Ok (R);
               if Order = Database.Indexes.Equal then
                  Leaf.Items.Delete (I);
                  Changed := True;
               elsif Order = Database.Indexes.Greater then
                  Beyond := True;
                  exit;
               else
                  I := I + 1;
               end if;
            end loop;
            if Database.Status.Is_Ok (R) and then Changed then
               R := Store (Tx, F, Leaf);
            end if;
            exit when not Database.Status.Is_Ok (R) or else Beyond or else Leaf.Next = Invalid_Page_Id;
         end;
         Steps := Steps + 1;
         if Steps > Limit then
            return Too_Deep;
         end if;
         R := Load (F, Leaf.Next, Leaf);
      end loop;
      return R;
   end Remove;

   function Update
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Old_Key   : Database.Values.Value;
      New_Key   : Database.Values.Value;
      New_Ref   : Database.Indexes.Row_Reference) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      R := Remove_Entry (Tx, F, Root, Old_Key, New_Ref);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Insert_Duplicate (Tx, F, Allocator, Root, New_Key, New_Ref);
   end Update;

   function Range_Find
     (F      : in out Database.Storage.File_IO.File_Handle;
      Root   : Database.Storage.Pages.Page_Id;
      Low    : Range_Bound;
      High   : Range_Bound;
      Result : out Row_Reference_Vectors.Vector) return Database.Status.Result
   is
      procedure Collect (Ref : Database.Indexes.Row_Reference; Stop : out Boolean) is
      begin
         Result.Append (Ref);
         Stop := False;
      end Collect;

      procedure Scan is new Scan_Range_Generic (Collect);
      R : Database.Status.Result;
   begin
      Result.Clear;
      Scan (F, Root, Low, High, R);
      return R;
   end Range_Find;

   function Pages_Of
     (F     : in out Database.Storage.File_IO.File_Handle;
      Root  : Database.Storage.Pages.Page_Id;
      Pages : out Page_Id_Vectors.Vector) return Database.Status.Result
   is
      Seen : Page_Sets.Set;
      Next : Natural := 0;
      N    : Node;
      R    : Database.Status.Result;
   begin
      Pages.Clear;
      Pages.Append (Root);
      if not Is_Built (F, Root) then
         return Database.Status.Success;
      end if;
      Seen.Insert (Root);
      while Next < Natural (Pages.Length) loop
         R := Load (F, Pages (Next), N);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if not N.Leaf then
            for Position in -1 .. Natural (N.Items.Length) - 1 loop
               declare
                  Child : constant Page_Id := (if Position < 0 then N.First else N.Items (Position).Child);
               begin
                  if Seen.Contains (Child) then
                     return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree page is reached twice");
                  end if;
                  Seen.Insert (Child);
                  Pages.Append (Child);
               end;
            end loop;
         end if;
         Next := Next + 1;
      end loop;
      return Database.Status.Success;
   end Pages_Of;

   function Validate
      (F    : in out Database.Storage.File_IO.File_Handle;
       Root : Database.Storage.Pages.Page_Id) return Database.Status.Result is
      Page  : Database.Storage.Pages.Page;
      Pages : Page_Id_Vectors.Vector;
      R     : Database.Status.Result;
   begin
      if Root = Invalid_Page_Id then
         return Database.Status.Failure
           (Database.Status.Corrupt_Index, "invalid btree root page");
      end if;
      R := Database.Storage.File_IO.Read_Raw_Page (F, Root, Page);
      if not Database.Status.Is_Ok (R) or else not Is_Built (F, Root) then
         return R;
      end if;
      R := Pages_Of (F, Root, Pages);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      --  Every node holds its entries in strictly ascending (key, reference) order.
      for Id of Pages loop
         declare
            N     : Node;
            Order : Database.Indexes.Ordering;
         begin
            R := Load (F, Id, N);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            for I in 1 .. Natural (N.Items.Length) - 1 loop
               R := Compare (N.Items (I - 1).Key, N.Items (I - 1).Ref, N.Items (I).Key, N.Items (I).Ref, Order);
               if not Database.Status.Is_Ok (R) or else Order /= Database.Indexes.Less then
                  return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree node is out of order");
               end if;
            end loop;
         end;
      end loop;
      return Database.Status.Success;
   end Validate;

end Database.Indexes.BTree;
