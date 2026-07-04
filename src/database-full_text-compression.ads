--  Full-text posting compression helpers.
--
--  The routines in this package are intentionally small and deterministic:
--  natural values are encoded as base-128 varints and sorted term positions
--  are encoded as gaps.  They are used by the native full-text page helpers
--  and are public so integrity tests can verify the exact storage contract.
with Ada.Containers.Vectors;
with Database.Storage.Pages;
with Database.Full_Text.Postings;

--  Public specification for this database subsystem.
package Database.Full_Text.Compression is
   use type Database.Storage.Pages.Byte;
   --  Byte_Vectors stores ordered byte values for this package.
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Database.Storage.Pages.Byte);

   --  Perform append varint for the supplied database state or arguments.
   --  @param Bytes byte data processed by the operation.
   --  @param Value typed value supplied to the operation.
   procedure Append_Varint
     (Bytes : in out Byte_Vectors.Vector;
      Value : Natural);

   --  Return decode varint for the supplied database state or arguments.
   --  @param Bytes byte data processed by the operation.
   --  @param Offset offset argument supplied to the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Decode_Varint
     (Bytes  : Byte_Vectors.Vector;
      Offset : in out Natural;
      Value  : out Natural) return Boolean;

   --  Return encode positions for the supplied database state or arguments.
   --  @param Positions positions argument supplied to the operation.
   --  @return Result produced by the function.
   function Encode_Positions
     (Positions : Database.Full_Text.Postings.Position_Vectors.Vector)
      return Byte_Vectors.Vector;

   --  Return decode positions for the supplied database state or arguments.
   --  @param Bytes byte data processed by the operation.
   --  @return Result produced by the function.
   function Decode_Positions
     (Bytes : Byte_Vectors.Vector)
      return Database.Full_Text.Postings.Position_Vectors.Vector;

   --  Return encoded length for the supplied database state or arguments.
   --  @param Positions positions argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Encoded_Length
     (Positions : Database.Full_Text.Postings.Position_Vectors.Vector) return Natural;
end Database.Full_Text.Compression;
