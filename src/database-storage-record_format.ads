--  Explicit row/value serialization format. Ada record memory is never serialized.
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;

   --  Public nested package `Database.Storage.Record_Format`.
package Database.Storage.Record_Format is
   --  Public type `Byte_Vector`.
   type Byte_Vector is record
      Data : Database.Storage.Pages.Byte_Array (0 .. Database.Storage.Pages.Payload_Capacity - 1) := (others => 0);
      Last : Natural := 0;
   end record;

   --  Public operation `Serialize`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Serialize
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Result : out Byte_Vector) return Database.Status.Result;

   --  Public operation `Deserialize`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Data byte data processed by the operation.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Deserialize
     (Schema : Database.Schema.Table_Schema;
      Data   : Database.Storage.Pages.Byte_Array;
      Row    : out Database.Rows.Row) return Database.Status.Result;
end Database.Storage.Record_Format;
