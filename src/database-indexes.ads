--  Index metadata, key comparison, and index validation helpers.
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers.Indefinite_Vectors;
with Database.Status;
with Database.Storage.Pages;
with Database.Rows;
with Database.Types;
with Database.Values;

   --  Public nested package `Database.Indexes`.
package Database.Indexes is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Public type `Index_Id`.
   type Index_Id is new Natural;
   --  Public type `Index_Kind`.
   type Index_Kind is (Primary_Key_Index, Unique_Index, Secondary_Index, Partial_Index, Expression_Index);

   --  Public type `Row_Reference`.
   type Row_Reference is record
      Page : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Slot_Offset : Natural := 0;
   end record;

   --  Invalid_Row_Reference is a public constant used by this package.
   Invalid_Row_Reference : constant Row_Reference  :=
     (Page => Database.Storage.Pages.Invalid_Page_Id, Slot_Offset => 0);

   --  Column_Id_Vectors stores ordered column id values for this package.
   package Column_Id_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Natural);

   --  Composite_Key stores the public fields for this database abstraction.
   type Composite_Key is record
      Parts : Database.Rows.Value_Vectors.Vector;
   end record;

   --  Public type `Index_Metadata`.
   type Index_Metadata is record
      Id        : Index_Id := 0;
      Table_Id  : Natural := 0;
      Name      : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Kind      : Index_Kind := Primary_Key_Index;
      Root_Page : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Unique    : Boolean := True;
      Column_Id : Natural := 0;
      Key_Kind  : Database.Types.Value_Kind := Database.Types.Null_Value;
      Column_Ids : Column_Id_Vectors.Vector;
      Has_Predicate : Boolean := False;
      Has_Expression : Boolean := False;
   end record;

   --  Public nested package `Index_Metadata_Vectors`.
   package Index_Metadata_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Index_Metadata);

   --  Public type `Ordering`.
   type Ordering is (Less, Equal, Greater);

   --  Public operation `Supports_Key`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Kind kind selector controlling the operation.
   --  @return Result produced by the function.
   function Supports_Key (Kind : Database.Types.Value_Kind) return Boolean;
   --  Public operation `Compare`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Order order argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : Database.Values.Value; Order : out Ordering) return Database.Status.Result;
   --  Public operation `Validate_Key`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Key key value used to identify the row or object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Key (Key : Database.Values.Value) return Database.Status.Result;
   --  Return compare composite for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Order order argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare_Composite (Left, Right : Composite_Key; Order : out Ordering) return Database.Status.Result;
   --  Return validate composite key for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Composite_Key (Key : Composite_Key) return Database.Status.Result;
   --  Public operation `Validate_Secondary_Key`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Key key value used to identify the row or object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Secondary_Key (Key : Database.Values.Value) return Database.Status.Result;
   --  Public operation `Metadata_Name`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Table_Name table name argument supplied to the operation.
   --  @return Result produced by the function.
   function Metadata_Name (Table_Name : Wide_Wide_String) return Unbounded_Wide_Wide_String;

   --  Public operation `Validate_Index_Metadata`. See the package documentation for transaction, ownership, and
   --  error-result semantics.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Index_Metadata (Index : Index_Metadata) return Database.Status.Result;
   --  Public operation `Validate_Row_Reference`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Ref ref argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Row_Reference (Ref : Row_Reference) return Database.Status.Result;
   --  Public operation `Validate_Key_Ordering`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Previous previous argument supplied to the operation.
   --  @param Current current argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Key_Ordering
     (Previous : Database.Values.Value;
      Current  : Database.Values.Value) return Database.Status.Result;
end Database.Indexes;
