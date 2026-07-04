--  Ordered row container used by schemas, typed table mappings, and storage.
with Ada.Containers.Indefinite_Vectors;
with Database.Values;
use Database.Values;

   --  Public nested package `Database.Rows`.
package Database.Rows is
   --  Public nested package `Value_Vectors`.
   package Value_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Values.Value);

   --  Public type `Row`.
   type Row is record
      Values : Value_Vectors.Vector;
   end record;

   --  Compares two rows for value-by-value equality.
   --  @param Left Left row operand.
   --  @param Right Right row operand.
   --  @return True when both rows contain the same values in the same order.
   overriding function "=" (Left, Right : Row) return Boolean;

   --  Public operation `Append`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param R r argument supplied to the operation.
   --  @param V v argument supplied to the operation.
   procedure Append (R : in out Row; V : Database.Values.Value);
   --  Public operation `Column_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param R r argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Column_Count (R : Row) return Natural;
   --  Public operation `Get`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param R r argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Requested value or optional value according to the package contract.
   function Get (R : Row; Index : Natural) return Database.Values.Value;
   --  Public operation `Replace`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param R r argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param V v argument supplied to the operation.
   procedure Replace (R : in out Row; Index : Natural; V : Database.Values.Value);
end Database.Rows;
