with Ada.Containers;

package body Database.Full_Text.Compression is
   use type Ada.Containers.Count_Type;
   use type Database.Storage.Pages.Byte;

   procedure Append_Varint
     (Bytes : in out Byte_Vectors.Vector;
      Value : Natural) is
      Remaining : Natural := Value;
      B         : Database.Storage.Pages.Byte;
   begin
      loop
         B := Database.Storage.Pages.Byte (Remaining mod 128);
         Remaining := Remaining / 128;
         if Remaining /= 0 then
            B := B + Database.Storage.Pages.Byte (128);
         end if;
         Bytes.Append (B);
         exit when Remaining = 0;
      end loop;
   end Append_Varint;

   function Decode_Varint
     (Bytes  : Byte_Vectors.Vector;
      Offset : in out Natural;
      Value  : out Natural) return Boolean is
      Shift : Natural := 0;
      Acc   : Natural := 0;
      B     : Natural;
   begin
      Value := 0;
      while Offset < Natural (Bytes.Length) loop
         B := Natural (Bytes.Element (Offset));
         if Shift >= Natural'Size then
            return False;
         end if;
         Acc := Acc + (B mod 128) * (2 ** Shift);
         Offset := Offset + 1;
         if B < 128 then
            Value := Acc;
            return True;
         end if;
         Shift := Shift + 7;
      end loop;
      return False;
   end Decode_Varint;

   function Encode_Positions
     (Positions : Database.Full_Text.Postings.Position_Vectors.Vector)
      return Byte_Vectors.Vector is
      Bytes    : Byte_Vectors.Vector;
      Previous : Natural := 0;
      Gap      : Natural;
   begin
      Append_Varint (Bytes, Natural (Positions.Length));
      for Position of Positions loop
         if Position >= Previous then
            Gap := Position - Previous;
         else
            --  Position vectors should be monotonic in normal index data.  Keep
            --  the encoder total by storing a zero gap for malformed caller
            --  input;
            --  Database.Check is responsible for rejecting malformed
            --  posting order when reading real indexes.
            Gap := 0;
         end if;
         Append_Varint (Bytes, Gap);
         Previous := Position;
      end loop;
      return Bytes;
   end Encode_Positions;

   function Decode_Positions
     (Bytes : Byte_Vectors.Vector)
      return Database.Full_Text.Postings.Position_Vectors.Vector is
      Positions : Database.Full_Text.Postings.Position_Vectors.Vector;
      Offset    : Natural := 0;
      Count     : Natural := 0;
      Gap       : Natural := 0;
      Current   : Natural := 0;
      Ok        : Boolean;
   begin
      Ok := Decode_Varint (Bytes, Offset, Count);
      if not Ok then
         return Positions;
      end if;

      for I in 1 .. Count loop
         Ok := Decode_Varint (Bytes, Offset, Gap);
         exit when not Ok;
         Current := Current + Gap;
         Positions.Append (Current);
      end loop;
      return Positions;
   end Decode_Positions;

   function Encoded_Length
     (Positions : Database.Full_Text.Postings.Position_Vectors.Vector) return Natural is
      Bytes : constant Byte_Vectors.Vector := Encode_Positions (Positions);
   begin
      return Natural (Bytes.Length);
   end Encoded_Length;
end Database.Full_Text.Compression;
