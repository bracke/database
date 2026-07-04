with Ada.Containers;
with Database.Full_Text.Compression;
with Database.Versioning;

package body Database.Full_Text.Storage is
   use type Ada.Containers.Count_Type;
   use type Database.Storage.Pages.Byte;
   use type Database.Storage.Pages.Page_Kind;

   subtype Byte is Database.Storage.Pages.Byte;
   package Byte_Vectors renames Database.Full_Text.Compression.Byte_Vectors;

   procedure Append_Varint
     (Bytes : in out Byte_Vectors.Vector;
      Value : Natural) renames Database.Full_Text.Compression.Append_Varint;

   function Decode_Varint
     (Bytes  : Byte_Vectors.Vector;
      Offset : in out Natural;
      Value  : out Natural) return Boolean
      renames Database.Full_Text.Compression.Decode_Varint;

   procedure Append_Text (Bytes : in out Byte_Vectors.Vector; Text : Wide_Wide_String) is
   begin
      Append_Varint (Bytes, Text'Length);
      for Ch of Text loop
         Append_Varint (Bytes, Wide_Wide_Character'Pos (Ch));
      end loop;
   end Append_Text;

   function Decode_Text
     (Bytes  : Byte_Vectors.Vector;
      Offset : in out Natural;
      Text   : out Unbounded_Wide_Wide_String) return Boolean is
      Count : Natural := 0;
      Code  : Natural := 0;
   begin
      Text := Null_Unbounded_Wide_Wide_String;
      if not Decode_Varint (Bytes, Offset, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         if not Decode_Varint (Bytes, Offset, Code) then
            return False;
         end if;
         if Code > Wide_Wide_Character'Pos (Wide_Wide_Character'Last) then
            return False;
         end if;
         Append (Text, Wide_Wide_Character'Val (Code));
      end loop;
      return True;
   end Decode_Text;

   function To_Byte_Array (Bytes : Byte_Vectors.Vector) return Database.Storage.Pages.Byte_Array is
      Result : Database.Storage.Pages.Byte_Array (0 .. Natural (Bytes.Length) - 1);
   begin
      if Bytes.Length = 0 then
         declare
            Empty : Database.Storage.Pages.Byte_Array (1 .. 0);
         begin return Empty;
         end;
      end if;
      for I in 0 .. Natural (Bytes.Length) - 1 loop
         Result (I) := Bytes.Element (I);
      end loop;
      return Result;
   end To_Byte_Array;

   function From_Byte_Array (Data : Database.Storage.Pages.Byte_Array) return Byte_Vectors.Vector is
      Bytes : Byte_Vectors.Vector;
   begin
      for I in Data'Range loop
         Bytes.Append (Data (I));
      end loop;
      return Bytes;
   end From_Byte_Array;

   procedure Append_Posting
     (Bytes : in out Byte_Vectors.Vector;
      P     : Database.Full_Text.Postings.Posting) is
      Encoded_Positions : constant Byte_Vectors.Vector  :=
        Database.Full_Text.Compression.Encode_Positions (P.Positions);
   begin
      Append_Varint (Bytes, P.Ref.Table_Id);
      Append_Varint (Bytes, P.Ref.Row_Id);
      Append_Text (Bytes, To_Wide_Wide_String (P.Ref.Row_Key));
      Append_Varint (Bytes, P.Ref.Column_Id);
      Append_Varint (Bytes, P.Frequency);
      Append_Varint (Bytes, Natural (P.Created_By));
      Append_Varint (Bytes, Natural (P.Created_At));
      Append_Varint (Bytes, Natural (P.Deleted_By));
      Append_Varint (Bytes, Natural (P.Deleted_At));
      Append_Varint (Bytes, Natural (Encoded_Positions.Length));
      for B of Encoded_Positions loop
         Bytes.Append (B);
      end loop;
   end Append_Posting;

   function Decode_Posting
     (Bytes  : Byte_Vectors.Vector;
      Offset : in out Natural;
      P      : out Database.Full_Text.Postings.Posting) return Boolean is
      V       : Natural := 0;
      Key     : Unbounded_Wide_Wide_String;
      Pos_Len : Natural := 0;
      Enc     : Byte_Vectors.Vector;
   begin
      P := (others => <>);
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Ref.Table_Id := V;
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Ref.Row_Id := V;
      if not Decode_Text (Bytes, Offset, Key) then
         return False;
      end if;
      P.Ref.Row_Key := Key;
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Ref.Column_Id := V;
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Frequency := V;
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Created_By := Database.Versioning.Transaction_Id (V);
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Created_At := Database.Versioning.Commit_Version (V);
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Deleted_By := Database.Versioning.Transaction_Id (V);
      if not Decode_Varint (Bytes, Offset, V) then
         return False;
      end if;
      P.Deleted_At := Database.Versioning.Commit_Version (V);
      if not Decode_Varint (Bytes, Offset, Pos_Len) then
         return False;
      end if;
      if Offset + Pos_Len > Natural (Bytes.Length) then
         return False;
      end if;
      for I in 1 .. Pos_Len loop
         Enc.Append (Bytes.Element (Offset));
         Offset := Offset + 1;
      end loop;
      P.Positions := Database.Full_Text.Compression.Decode_Positions (Enc);
      return True;
   end Decode_Posting;

   function Build_Dictionary_Page
     (Id           : Database.Storage.Pages.Page_Id;
      Term         : Wide_Wide_String;
      Posting_Root : Database.Storage.Pages.Page_Id) return Database.Storage.Pages.Page is
      P     : Database.Storage.Pages.Page;
      Bytes : Byte_Vectors.Vector;
   begin
      Database.Storage.Pages.Initialize (P, Id, Database.Storage.Pages.Full_Text_Dictionary_Page);
      Append_Varint (Bytes, Native_Format_Version);
      Append_Text (Bytes, Term);
      Append_Varint (Bytes, Natural (Posting_Root));
      Database.Storage.Pages.Set_Payload (P, To_Byte_Array (Bytes));
      return P;
   end Build_Dictionary_Page;

   function Parse_Dictionary_Page
     (P            : Database.Storage.Pages.Page;
      Term         : out Unbounded_Wide_Wide_String;
      Posting_Root : out Database.Storage.Pages.Page_Id) return Database.Status.Result is
      Bytes  : constant Byte_Vectors.Vector := From_Byte_Array (Database.Storage.Pages.Payload (P));
      Offset : Natural := 0;
      V      : Natural := 0;
   begin
      Term := Null_Unbounded_Wide_Wide_String;
      Posting_Root := Database.Storage.Pages.Invalid_Page_Id;
      if Database.Storage.Pages.Get_Kind (P) /= Database.Storage.Pages.Full_Text_Dictionary_Page then
         return Database.Status.Failure (Database.Status.Corrupt_File, "not a full-text dictionary page");
      end if;
      if not Decode_Varint (Bytes, Offset, V) or else V /= Native_Format_Version then
         return Database.Status.Failure (Database.Status.Corrupt_File, "unsupported full-text dictionary page version");
      end if;
      if not Decode_Text (Bytes, Offset, Term) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text dictionary term");
      end if;
      if not Decode_Varint (Bytes, Offset, V) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting root");
      end if;
      Posting_Root := Database.Storage.Pages.Page_Id (V);
      return Database.Status.Success;
   end Parse_Dictionary_Page;

   function Build_Posting_Page
     (Id       : Database.Storage.Pages.Page_Id;
      Term     : Wide_Wide_String;
      Postings : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Next     : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id)
      return Database.Storage.Pages.Page is
      P     : Database.Storage.Pages.Page;
      Bytes : Byte_Vectors.Vector;
   begin
      Database.Storage.Pages.Initialize (P, Id, Database.Storage.Pages.Full_Text_Posting_Page, Next);
      Append_Varint (Bytes, Native_Format_Version);
      Append_Text (Bytes, Term);
      Append_Varint (Bytes, Natural (Postings.Length));
      for Posting of Postings loop
         Append_Posting (Bytes, Posting);
      end loop;
      Database.Storage.Pages.Set_Payload (P, To_Byte_Array (Bytes));
      return P;
   end Build_Posting_Page;

   function Parse_Posting_Page
     (P        : Database.Storage.Pages.Page;
      Term     : out Unbounded_Wide_Wide_String;
      Postings : out Database.Full_Text.Postings.Posting_Vectors.Vector)
      return Database.Status.Result is
      Bytes  : constant Byte_Vectors.Vector := From_Byte_Array (Database.Storage.Pages.Payload (P));
      Offset : Natural := 0;
      V      : Natural := 0;
      Count  : Natural := 0;
      Item   : Database.Full_Text.Postings.Posting;
   begin
      Term := Null_Unbounded_Wide_Wide_String;
      Postings.Clear;
      if Database.Storage.Pages.Get_Kind (P) /= Database.Storage.Pages.Full_Text_Posting_Page then
         return Database.Status.Failure (Database.Status.Corrupt_File, "not a full-text posting page");
      end if;
      if not Decode_Varint (Bytes, Offset, V) or else V /= Native_Format_Version then
         return Database.Status.Failure (Database.Status.Corrupt_File, "unsupported full-text posting page version");
      end if;
      if not Decode_Text (Bytes, Offset, Term) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting term");
      end if;
      if not Decode_Varint (Bytes, Offset, Count) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting count");
      end if;
      for I in 1 .. Count loop
         if not Decode_Posting (Bytes, Offset, Item) then
            return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting payload");
         end if;
         Postings.Append (Item);
      end loop;
      return Database.Status.Success;
   end Parse_Posting_Page;
end Database.Full_Text.Storage;
