with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;

package body Database.Indexes.BTree is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;
   use type Database.Storage.Pages.Page_Id;

   type Index_Entry is record
      Key  : Database.Values.Value := Database.Values.Null_Value;
      Refs : Row_Reference_Vectors.Vector;
   end record;

   package Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Index_Entry);

   type Tree is record
      Root    : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Path    : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Entries : Entry_Vectors.Vector;
   end record;

   package Tree_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Tree);

   Trees : Tree_Vectors.Vector;

   function Tree_Position
     (Path : Wide_Wide_String;
      Root : Database.Storage.Pages.Page_Id) return Natural is
   begin
      if Trees.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Trees.Length) - 1 loop
         if Trees.Element (I).Root = Root
           and then To_Wide_Wide_String (Trees.Element (I).Path) = Path
         then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Tree_Position;

   procedure Ensure_Tree
     (Path : Wide_Wide_String;
      Root : Database.Storage.Pages.Page_Id) is
   begin
      if Root = Database.Storage.Pages.Invalid_Page_Id then
         return;
      end if;
      if Tree_Position (Path, Root) = Natural'Last then
         Trees.Append
           (Tree'
              (Root    => Root,
               Path    => To_Unbounded_Wide_Wide_String (Path),
               Entries => Entry_Vectors.Empty_Vector));
      end if;
   end Ensure_Tree;

   function Entry_Position
     (T     : Tree;
      Key   : Database.Values.Value;
      Found : out Boolean;
      Valid : out Database.Status.Result) return Natural is
      Order : Database.Indexes.Ordering;
      R     : Database.Status.Result;
   begin
      Found := False;
      Valid := Database.Status.Success;
      if T.Entries.Length = 0 then
         return 0;
      end if;
      for I in 0 .. Natural (T.Entries.Length) - 1 loop
         R := Database.Indexes.Compare (T.Entries.Element (I).Key, Key, Order);
         if not Database.Status.Is_Ok (R) then
            Valid := R;
            return Natural'Last;
         end if;
         if Order = Database.Indexes.Equal then
            Found := True;
            return I;
         elsif Order = Database.Indexes.Greater then
            return I;
         end if;
      end loop;
      return Natural (T.Entries.Length);
   end Entry_Position;

   function Ref_Equals
     (Left, Right : Database.Indexes.Row_Reference) return Boolean is
   begin
      return Left.Page = Right.Page and then Left.Slot_Offset = Right.Slot_Offset;
   end Ref_Equals;

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

   function Create
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : out Database.Storage.Pages.Page_Id) return Database.Status.Result is
      pragma Unreferenced (Tx);
      Page : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
   begin
      R := Database.Storage.Free_List.Allocate
        (Allocator, F, Database.Storage.Pages.BTree_Leaf_Page, Page);
      if not Database.Status.Is_Ok (R) then
         Root := Database.Storage.Pages.Invalid_Page_Id;
         return R;
      end if;
      Root := Database.Storage.Pages.Get_Id (Page);
      Ensure_Tree (Database.Storage.File_IO.Path (F), Root);
      return Database.Status.Success;
   end Create;

   function Insert
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result is
      Page  : Database.Storage.Pages.Page;
      R     : Database.Status.Result;
      T_Pos : Natural;
      E_Pos : Natural;
      Found : Boolean;
      Valid : Database.Status.Result;
   begin
      if Root = Database.Storage.Pages.Invalid_Page_Id then
         R := Create (Tx, F, Allocator, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      elsif Tree_Position (Database.Storage.File_IO.Path (F), Root) = Natural'Last then
         R := Database.Storage.File_IO.Read_Raw_Page (F, Root, Page);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         Ensure_Tree (Database.Storage.File_IO.Path (F), Root);
      end if;
      T_Pos := Tree_Position (Database.Storage.File_IO.Path (F), Root);
      declare
         T : Tree := Trees.Element (T_Pos);
         E : Index_Entry;
      begin
         E_Pos := Entry_Position (T, Key, Found, Valid);
         if not Database.Status.Is_Ok (Valid) then
            return Valid;
         end if;
         if Found then
            return Database.Status.Failure
              (Database.Status.Duplicate_Key, "duplicate index key");
         end if;
         E.Key := Key;
         E.Refs.Append (Ref);
         T.Entries.Insert (E_Pos, E);
         Trees.Replace_Element (T_Pos, T);
      end;
      return Database.Status.Success;
   end Insert;

   function Find
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : out Database.Indexes.Row_Reference) return Database.Status.Result is
      T_Pos : constant Natural :=
        Tree_Position (Database.Storage.File_IO.Path (F), Root);
      E_Pos : Natural;
      Found : Boolean;
      Valid : Database.Status.Result;
   begin
      Ref := Database.Indexes.Invalid_Row_Reference;
      if T_Pos = Natural'Last then
         return Database.Status.Failure
           (Database.Status.Key_Not_Found, "index key not found");
      end if;
      declare
         T : constant Tree := Trees.Element (T_Pos);
      begin
         E_Pos := Entry_Position (T, Key, Found, Valid);
         if not Database.Status.Is_Ok (Valid) then
            return Valid;
         end if;
         if Found and then T.Entries.Element (E_Pos).Refs.Length > 0 then
            Ref := T.Entries.Element (E_Pos).Refs.Element (0);
            return Database.Status.Success;
         end if;
      end;
      return Database.Status.Failure
        (Database.Status.Key_Not_Found, "index key not found");
   end Find;

   function Insert_Duplicate
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result is
      Page  : Database.Storage.Pages.Page;
      R     : Database.Status.Result;
      T_Pos : Natural;
      E_Pos : Natural;
      Found : Boolean;
      Valid : Database.Status.Result;
   begin
      if Root = Database.Storage.Pages.Invalid_Page_Id then
         R := Create (Tx, F, Allocator, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      elsif Tree_Position (Database.Storage.File_IO.Path (F), Root) = Natural'Last then
         R := Database.Storage.File_IO.Read_Raw_Page (F, Root, Page);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         Ensure_Tree (Database.Storage.File_IO.Path (F), Root);
      end if;
      T_Pos := Tree_Position (Database.Storage.File_IO.Path (F), Root);
      declare
         T : Tree := Trees.Element (T_Pos);
         E : Index_Entry;
      begin
         E_Pos := Entry_Position (T, Key, Found, Valid);
         if not Database.Status.Is_Ok (Valid) then
            return Valid;
         end if;
         if Found then
            E := T.Entries.Element (E_Pos);
            E.Refs.Append (Ref);
            T.Entries.Replace_Element (E_Pos, E);
         else
            E.Key := Key;
            E.Refs.Append (Ref);
            T.Entries.Insert (E_Pos, E);
         end if;
         Trees.Replace_Element (T_Pos, T);
      end;
      return Database.Status.Success;
   end Insert_Duplicate;

   function Remove_Entry
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result is
      pragma Unreferenced (Tx);
      T_Pos : constant Natural :=
        Tree_Position (Database.Storage.File_IO.Path (F), Root);
      E_Pos : Natural;
      Found : Boolean;
      Valid : Database.Status.Result;
   begin
      if T_Pos = Natural'Last then
         return Database.Status.Success;
      end if;
      declare
         T : Tree := Trees.Element (T_Pos);
         E : Index_Entry;
      begin
         E_Pos := Entry_Position (T, Key, Found, Valid);
         if not Database.Status.Is_Ok (Valid) then
            return Valid;
         end if;
         if Found then
            E := T.Entries.Element (E_Pos);
            if E.Refs.Length > 0 then
               for I in reverse 0 .. Natural (E.Refs.Length) - 1 loop
                  if Ref_Equals (E.Refs.Element (I), Ref) then
                     E.Refs.Delete (I);
                  end if;
               end loop;
            end if;
            if E.Refs.Length = 0 then
               T.Entries.Delete (E_Pos);
            else
               T.Entries.Replace_Element (E_Pos, E);
            end if;
            Trees.Replace_Element (T_Pos, T);
         end if;
      end;
      return Database.Status.Success;
   end Remove_Entry;

   function Remove
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value) return Database.Status.Result is
      pragma Unreferenced (Tx);
      T_Pos : constant Natural :=
        Tree_Position (Database.Storage.File_IO.Path (F), Root);
      E_Pos : Natural;
      Found : Boolean;
      Valid : Database.Status.Result;
   begin
      if T_Pos = Natural'Last then
         return Database.Status.Success;
      end if;
      declare
         T : Tree := Trees.Element (T_Pos);
      begin
         E_Pos := Entry_Position (T, Key, Found, Valid);
         if not Database.Status.Is_Ok (Valid) then
            return Valid;
         end if;
         if Found then
            T.Entries.Delete (E_Pos);
            Trees.Replace_Element (T_Pos, T);
         end if;
      end;
      return Database.Status.Success;
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
      Result : out Row_Reference_Vectors.Vector) return Database.Status.Result is
      T_Pos : constant Natural :=
        Tree_Position (Database.Storage.File_IO.Path (F), Root);
   begin
      Result.Clear;
      if T_Pos = Natural'Last then
         return Database.Status.Success;
      end if;
      declare
         T : constant Tree := Trees.Element (T_Pos);
      begin
         for E of T.Entries loop
            if Within_Bound (E.Key, Low, True)
              and then Within_Bound (E.Key, High, False)
            then
               for Ref of E.Refs loop
                  Result.Append (Ref);
               end loop;
            end if;
         end loop;
      end;
      return Database.Status.Success;
   end Range_Find;

   function Validate
      (F    : in out Database.Storage.File_IO.File_Handle;
       Root : Database.Storage.Pages.Page_Id) return Database.Status.Result is
      Page : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
   begin
      if Root = Database.Storage.Pages.Invalid_Page_Id then
         return Database.Status.Failure
           (Database.Status.Corrupt_Index, "invalid btree root page");
      end if;
      R := Database.Storage.File_IO.Read_Raw_Page (F, Root, Page);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Database.Status.Success;
   end Validate;

end Database.Indexes.BTree;
