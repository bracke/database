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

   --  Internal nodes are never merged and keep at least one separator, so every level at least doubles the pages
   --  below it: a tree of 2**32 pages is at most 32 levels high. A deeper path can only come from a corrupt file.
   Max_Height : constant := 64;

   function Corrupt (Message : Wide_Wide_String) return Database.Status.Result is
     (Database.Status.Failure (Database.Status.Corrupt_Index, Message));

   --  The database a write transaction changes; null when the transaction cannot change index pages.
   function Database_Of (Tx : in out Database.Transactions.Transaction) return access Database.Handle is
      DB : constant access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB = null or else Database."/=" (Database.Backend (DB.all), Database.Persistent_Backend) then
         return null;
      end if;
      return DB;
   end Database_Of;

   function Not_Writable return Database.Status.Result is
     (Database.Status.Failure
        (Database.Status.Transaction_Error, "index pages change only in a write transaction of a persistent database"));

   function Walk
     (F           : in out Database.Storage.File_IO.File_Handle;
      Root        : Page_Id;
      Check_Order : Boolean;
      Pages       : out Page_Id_Vectors.Vector) return Database.Status.Result;

   --  Whether Key lies on the inner side of Bound: above a lower bound (Low) or below an upper one.
   function Within_Bound
     (Key    : Database.Values.Value;
      Bound  : Range_Bound;
      Low    : Boolean;
      Inside : out Boolean) return Database.Status.Result
   is
      Order : Database.Indexes.Ordering;
      R     : Database.Status.Result;
   begin
      Inside := True;
      if Bound.Kind = Unbounded then
         return Database.Status.Success;
      end if;
      R := Database.Indexes.Compare (Key, Bound.Key, Order);
      if Database.Status.Is_Ok (R) then
         Inside := Order = (if Low then Database.Indexes.Greater else Database.Indexes.Less)
           or else (Bound.Kind = Inclusive and then Order = Database.Indexes.Equal);
      end if;
      return R;
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
     (Tx   : in out Database.Transactions.Transaction;
      Leaf : Boolean;
      Id   : out Page_Id) return Database.Status.Result
   is
      Page : Database.Storage.Pages.Page;
      R    : constant Database.Status.Result :=
        Database.Transactions.Allocate_Page (Tx, (if Leaf then BTree_Leaf_Page else BTree_Internal_Page), Page);
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
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      N    : in out Node;
      Path : in out Page_Id_Vectors.Vector) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      loop
         if Fits (N) then
            return Store (Tx, N);
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
            R := Allocate (Tx, N.Leaf, Right.Id);
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
               R := Allocate (Tx, N.Leaf, Left.Id);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               R := Store (Tx, Left);
               if Database.Status.Is_Ok (R) then
                  R := Store (Tx, Right);
               end if;
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               N := (Id => N.Id, Leaf => False, First => Left.Id, Next => Invalid_Page_Id, Items => <>);
               N.Items.Append (Separator);
               return Store (Tx, N);
            end if;
            R := Store (Tx, Left);
            if Database.Status.Is_Ok (R) then
               R := Store (Tx, Right);
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
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result
   is
      Size  : constant Natural := Key_Size (Key);
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      Found : Boolean;
      R     : Database.Status.Result;
   begin
      if Size > Max_Key_Bytes then
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
         Leaf.Items.Insert (Position, Item'(Key => Key, Ref => Ref, Child => Invalid_Page_Id, Key_Length => Size));
      end;
      return Write_Back (Tx, F, Leaf, Path);
   end Add;

   function Reset
     (Tx   : in out Database.Transactions.Transaction;
      Root : Page_Id) return Database.Status.Result is (Store (Tx, (Id => Root, Leaf => True, others => <>)));

   function Create
     (Tx   : in out Database.Transactions.Transaction;
      Root : out Database.Storage.Pages.Page_Id) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      Root := Invalid_Page_Id;
      if Database_Of (Tx) = null then
         return Not_Writable;
      end if;
      R := Allocate (Tx, True, Root);
      if not Database.Status.Is_Ok (R) then
         Root := Invalid_Page_Id;
         return R;
      end if;
      return Reset (Tx, Root);
   end Create;

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

   function Clear
     (Tx   : in out Database.Transactions.Transaction;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result
   is
      DB    : constant access Database.Handle := Database_Of (Tx);
      Pages : Page_Id_Vectors.Vector;
      R     : Database.Status.Result;
   begin
      if DB = null then
         return Not_Writable;
      elsif Is_Built (DB.File, Root) then
         --  Only the pages of a sound tree are freed; a corrupt one could name pages that other structures use.
         R := Walk (DB.File, Root, Check_Order => True, Pages => Pages);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         for Id of Pages loop
            if Id /= Root then
               R := Database.Transactions.Free_Page (Tx, Id);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end if;
         end loop;
      elsif not Is_Unwritten (DB.File, Root) then
         return Corrupt ("index root is neither a B+ tree nor an unwritten page");
      end if;
      return Reset (Tx, Root);
   end Clear;

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
      Limit  : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Leaf   : Node;
      Path   : Page_Id_Vectors.Vector;
      Steps  : Natural := 0;
      Stop   : Boolean := False;
      Inside : Boolean;
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
            R := Within_Bound (Entry_Item.Key, High, False, Inside);
            if not Database.Status.Is_Ok (R) or else not Inside then
               return;
            end if;
            R := Within_Bound (Entry_Item.Key, Low, True, Inside);
            if not Database.Status.Is_Ok (R) then
               return;
            elsif Inside then
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

   --  Insert or Insert_Duplicate: create a missing root, leave an unbuilt index alone, and reject an existing key of a
   --  unique index. A unique insert descends twice, once to look for the key and once to place the entry: a single
   --  descent cannot do both, because a separator left by a deleted entry can send an entry with the same key to a
   --  leaf right of the first one.
   function Insert_Entry
     (Tx     : in out Database.Transactions.Transaction;
      Root   : in out Database.Storage.Pages.Page_Id;
      Key    : Database.Values.Value;
      Ref    : Database.Indexes.Row_Reference;
      Unique : Boolean) return Database.Status.Result
   is
      DB       : constant access Database.Handle := Database_Of (Tx);
      Existing : Database.Indexes.Row_Reference;
      R        : Database.Status.Result;
   begin
      if DB = null then
         return Not_Writable;
      elsif Root = Invalid_Page_Id then
         R := Create (Tx, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      elsif not Is_Built (DB.File, Root) then
         return Database.Status.Success;
      end if;
      if Unique then
         R := Find (DB.File, Root, Key, Existing);
         if Database.Status.Is_Ok (R) then
            return Database.Status.Failure (Database.Status.Duplicate_Key, "duplicate index key");
         elsif R.Code /= Database.Status.Key_Not_Found then
            return R;
         end if;
      end if;
      return Add (Tx, DB.File, Root, Key, Ref);
   end Insert_Entry;

   function Insert
     (Tx   : in out Database.Transactions.Transaction;
      Root : in out Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result is
     (Insert_Entry (Tx, Root, Key, Ref, Unique => True));

   function Insert_Duplicate
     (Tx   : in out Database.Transactions.Transaction;
      Root : in out Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result is
     (Insert_Entry (Tx, Root, Key, Ref, Unique => False));

   function Remove_Entry
     (Tx   : in out Database.Transactions.Transaction;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result
   is
      DB    : constant access Database.Handle := Database_Of (Tx);
      Leaf  : Node;
      Path  : Page_Id_Vectors.Vector;
      Found : Boolean;
      R     : Database.Status.Result;
   begin
      if DB = null then
         return Not_Writable;
      elsif not Is_Built (DB.File, Root) then
         return Database.Status.Success;
      end if;
      R := Leaf_For (DB.File, Root, Exact_Entry, Key, Ref, Leaf, Path);
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
      return Store (Tx, Leaf);
   end Remove_Entry;

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

   --  Walk the tree at a built Root depth first, listing every page in Pages, root first. Every walk checks that each
   --  node is readable, that no page is reached twice, and that the tree is no higher than Max_Height. With Check_Order
   --  it also checks the order of the entries: every node strictly ascending, every entry of a subtree between the
   --  separators around it, all leaves at the same depth and chained left to right. Pages holds the pages reached
   --  before a failure.
   function Walk
     (F           : in out Database.Storage.File_IO.File_Handle;
      Root        : Page_Id;
      Check_Order : Boolean;
      Pages       : out Page_Id_Vectors.Vector) return Database.Status.Result
   is
      --  A separator bounding a subtree, or no bound.
      type Bound is record
         Present : Boolean := False;
         Key     : Database.Values.Value;
         Ref     : Database.Indexes.Row_Reference;
      end record;

      Seen       : Page_Sets.Set;
      Leaves     : Page_Id_Vectors.Vector;
      Links      : Page_Id_Vectors.Vector;
      Leaf_Depth : Integer := -1;

      --  Whether (Key, Ref) compares to Edge as required: at or above a lower bound, below an upper one.
      function Respects
        (Edge : Bound; Key : Database.Values.Value; Ref : Database.Indexes.Row_Reference; Lower : Boolean)
         return Boolean
      is
         Order : Database.Indexes.Ordering;
      begin
         if not Edge.Present then
            return True;
         end if;
         return Database.Status.Is_Ok (Compare (Key, Ref, Edge.Key, Edge.Ref, Order))
           and then (if Lower then Order /= Database.Indexes.Less else Order = Database.Indexes.Less);
      end Respects;

      function Check_Entries (N : Node; Low, High : Bound) return Database.Status.Result is
         Order : Database.Indexes.Ordering;
         R     : Database.Status.Result;
      begin
         for I in 0 .. Natural (N.Items.Length) - 1 loop
            if I > 0 then
               R := Compare (N.Items (I - 1).Key, N.Items (I - 1).Ref, N.Items (I).Key, N.Items (I).Ref, Order);
               if not Database.Status.Is_Ok (R) or else Order /= Database.Indexes.Less then
                  return Corrupt ("B+ tree node is out of order");
               end if;
            end if;
            if not Respects (Low, N.Items (I).Key, N.Items (I).Ref, True)
              or else not Respects (High, N.Items (I).Key, N.Items (I).Ref, False)
            then
               return Corrupt ("B+ tree entry lies outside its parent's separators");
            end if;
         end loop;
         return Database.Status.Success;
      end Check_Entries;

      function Visit (Id : Page_Id; Depth : Natural; Low, High : Bound) return Database.Status.Result is
         N : Node;
         R : Database.Status.Result;
      begin
         if Depth > Max_Height then
            return Too_Deep;
         elsif Seen.Contains (Id) then
            return Corrupt ("B+ tree page is reached twice");
         end if;
         Seen.Insert (Id);
         Pages.Append (Id);
         R := Load (F, Id, N);
         if Database.Status.Is_Ok (R) and then Check_Order then
            R := Check_Entries (N, Low, High);
         end if;
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if N.Leaf then
            if Leaf_Depth < 0 then
               Leaf_Depth := Depth;
            elsif Leaf_Depth /= Depth and then Check_Order then
               return Corrupt ("B+ tree leaves are at different depths");
            end if;
            Leaves.Append (Id);
            Links.Append (N.Next);
            return Database.Status.Success;
         end if;
         for Position in -1 .. Natural (N.Items.Length) - 1 loop
            declare
               Child_Low  : constant Bound :=
                 (if Position < 0 then Low
                  else (Present => True, Key => N.Items (Position).Key, Ref => N.Items (Position).Ref));
               Child_High : constant Bound :=
                 (if Position = Natural (N.Items.Length) - 1 then High
                  else (Present => True, Key => N.Items (Position + 1).Key, Ref => N.Items (Position + 1).Ref));
            begin
               R := Visit ((if Position < 0 then N.First else N.Items (Position).Child), Depth + 1,
                           Child_Low, Child_High);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end;
         end loop;
         return Database.Status.Success;
      end Visit;

      R : constant Database.Status.Result := Visit (Root, 0, (others => <>), (others => <>));
   begin
      if not Database.Status.Is_Ok (R) or else not Check_Order then
         return R;
      end if;
      --  The leaves, met left to right, are chained in that order.
      for I in 0 .. Natural (Leaves.Length) - 1 loop
         if Links (I) /= (if I = Natural (Leaves.Length) - 1 then Invalid_Page_Id else Leaves (I + 1)) then
            return Corrupt ("B+ tree leaf chain does not follow the tree");
         end if;
      end loop;
      return Database.Status.Success;
   end Walk;

   function Pages_Of
     (F     : in out Database.Storage.File_IO.File_Handle;
      Root  : Database.Storage.Pages.Page_Id;
      Pages : out Page_Id_Vectors.Vector) return Database.Status.Result is
   begin
      if not Is_Built (F, Root) then
         Pages.Clear;
         Pages.Append (Root);
         return Database.Status.Success;
      end if;
      return Walk (F, Root, Check_Order => False, Pages => Pages);
   end Pages_Of;

   function Validate
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result
   is
      Pages : Page_Id_Vectors.Vector;
   begin
      if Root = Invalid_Page_Id then
         return Corrupt ("invalid btree root page");
      elsif not Is_Built (F, Root) then
         return (if Is_Unwritten (F, Root) then Database.Status.Success
                 else Corrupt ("index root is neither a B+ tree nor an unwritten page"));
      end if;
      return Walk (F, Root, Check_Order => True, Pages => Pages);
   end Validate;

end Database.Indexes.BTree;
