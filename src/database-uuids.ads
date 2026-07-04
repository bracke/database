--  UUID support with canonical RFC-4122 text form and stable byte ordering.
with Database.Status;
--  UUID generation, parsing, and formatting.
package Database.UUIDs is
   --  Byte defines a public database type used by this package.
   subtype Byte is Natural range 0 .. 255;
   --  UUID defines a public database type used by this package.
   type UUID is array (Natural range 0 .. 15) of Byte;

   --  Return nil uuid for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Nil_UUID return UUID;
   --  Return generate uuid for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Generate_UUID return UUID;
   --  Return parse uuid for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Parse_UUID (Text : Wide_Wide_String; Value : out UUID) return Database.Status.Result;
   --  Return uuid to string for the supplied database state or arguments.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function UUID_To_String (Value : UUID) return Wide_Wide_String;
   --  Return compare for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : UUID) return Integer;
end Database.UUIDs;
