with Database.Status;
with Interfaces;
with Database.Log_Sequence;

package body Database.Storage.Pages is
   use type Ada.Streams.Stream_Element_Offset;
   use type Database.Log_Sequence.Log_Sequence_Number;
   Magic_0 : constant Byte := 16#44#; -- D
   Magic_1 : constant Byte := 16#42#; -- B
   Magic_2 : constant Byte := 16#50#; -- P
   Magic_3 : constant Byte := 16#36#; -- 6
   Version : constant Byte := 1;

   procedure Put_U32 (B : in out Page_Buffer; Offset : Natural; V : Natural) is
   begin
      B (Offset + 0) := Byte ((V / 16#1000000#) mod 256);
      B (Offset + 1) := Byte ((V / 16#10000#) mod 256);
      B (Offset + 2) := Byte ((V / 16#100#) mod 256);
      B (Offset + 3) := Byte (V mod 256);
   end Put_U32;

   function Get_U32 (B : Page_Buffer; Offset : Natural) return Natural is
   begin
      return Natural (B (Offset)) * 16#1000000#
        + Natural (B (Offset + 1)) * 16#10000#
        + Natural (B (Offset + 2)) * 16#100#
        + Natural (B (Offset + 3));
   end Get_U32;

   procedure Put_U64
     (B      : in out Page_Buffer;
      Offset : Natural;
      V      : Database.Log_Sequence.Log_Sequence_Number) is
      X : Database.Log_Sequence.Log_Sequence_Number := V;
   begin
      for I in reverse 0 .. 7 loop
         B (Offset + I) := Byte (X mod 256);
         X := X / 256;
      end loop;
   end Put_U64;

   function Get_U64
     (B      : Page_Buffer;
      Offset : Natural) return Database.Log_Sequence.Log_Sequence_Number is
      R : Database.Log_Sequence.Log_Sequence_Number := 0;
   begin
      for I in 0 .. 7 loop
         R := R * 256 + Database.Log_Sequence.Log_Sequence_Number (B (Offset + I));
      end loop;
      return R;
   end Get_U64;

   function Checksum (B : Page_Buffer) return Natural is
      S : Natural := 0;
   begin
      for I in B'Range loop
         if I < 36 or else I > 39 then
            S := S + Natural (B (I));
         end if;
      end loop;
      return S;
   end Checksum;

   procedure Refresh_Checksum (P : in out Page) is
   begin
      Put_U32 (P.Buffer, 36, Checksum (P.Buffer));
   end Refresh_Checksum;

   procedure Initialize
     (P    : out Page;
      Id   : Page_Id;
      Kind : Page_Kind;
      Next : Page_Id := Invalid_Page_Id) is
   begin
      P.Buffer := (others => 0);
      P.Buffer (0) := Magic_0;
      P.Buffer (1) := Magic_1;
      P.Buffer (2) := Magic_2;
      P.Buffer (3) := Magic_3;
      P.Buffer (4) := Version;
      P.Buffer (5) := Byte (Page_Kind'Pos (Kind));
      Put_U32 (P.Buffer, 8, Natural (Id));
      Put_U32 (P.Buffer, 12, Natural (Next));
      Put_U32 (P.Buffer, 16, 0);
      Put_U64 (P.Buffer, 28, 0);
      Refresh_Checksum (P);
   end Initialize;

   function Validate
     (P             : Page;
      Expected_Id   : Page_Id;
      Expected_Kind : Page_Kind) return Database.Status.Result is
      K : Natural;
   begin
      if P.Buffer (0) /= Magic_0
        or else P.Buffer (1) /= Magic_1
        or else P.Buffer (2) /= Magic_2
        or else P.Buffer (3) /= Magic_3
      then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid page magic");
      end if;
      if P.Buffer (4) /= Version then
         return Database.Status.Failure (Database.Status.Corrupt_File, "unsupported page version");
      end if;
      if P.Buffer (6) /= 0 or else P.Buffer (7) /= 0 then
         return Database.Status.Failure (Database.Status.Corrupt_File, "reserved page header bytes are not zero");
      end if;
      K := Natural (P.Buffer (5));
      if K > Page_Kind'Pos (Page_Kind'Last) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid page kind");
      end if;
      if Page_Kind'Val (K) /= Expected_Kind then
         return Database.Status.Failure (Database.Status.Corrupt_File, "unexpected page kind");
      end if;
      if Get_Id (P) /= Expected_Id then
         return Database.Status.Failure (Database.Status.Corrupt_File, "page id mismatch");
      end if;
      if Used (P) > Payload_Capacity then
         return Database.Status.Failure (Database.Status.Corrupt_File, "page payload out of bounds");
      end if;
      if Get_U32 (P.Buffer, 36) /= Checksum (P.Buffer) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "page checksum mismatch");
      end if;
      return Database.Status.Success;
   end Validate;

   function Get_Id (P : Page) return Page_Id is (Page_Id (Get_U32 (P.Buffer, 8)));
   function Get_Kind (P : Page) return Page_Kind is (Page_Kind'Val (Natural (P.Buffer (5))));
   function Get_Next (P : Page) return Page_Id is (Page_Id (Get_U32 (P.Buffer, 12)));

   procedure Set_Next (P : in out Page; Next : Page_Id) is
   begin
      Put_U32 (P.Buffer, 12, Natural (Next));
      Refresh_Checksum (P);
   end Set_Next;

   function Used (P : Page) return Natural is (Get_U32 (P.Buffer, 16));

   function Last_LSN (P : Page) return Database.Log_Sequence.Log_Sequence_Number is
     (Get_U64 (P.Buffer, 28));

   procedure Set_Last_LSN
     (P   : in out Page;
      LSN : Database.Log_Sequence.Log_Sequence_Number) is
   begin
      Put_U64 (P.Buffer, 28, LSN);
      Refresh_Checksum (P);
   end Set_Last_LSN;

   procedure Set_Used (P : in out Page; Used : Natural) is
   begin
      if Used <= Payload_Capacity then
         Put_U32 (P.Buffer, 16, Used);
         Refresh_Checksum (P);
      end if;
   end Set_Used;

   function Payload (P : Page) return Byte_Array is
      U : constant Natural := Used (P);
   begin
      if U = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            return Empty;
         end;
      else
         declare
            R : Byte_Array (0 .. U - 1);
         begin
            for I in 0 .. U - 1 loop
               R (I) := P.Buffer (Header_Size + I);
            end loop;
            return R;
         end;
      end if;
   end Payload;

   procedure Set_Payload (P : in out Page; Data : Byte_Array) is
   begin
      if Data'Length <= Payload_Capacity then
         for I in 0 .. Payload_Capacity - 1 loop
            P.Buffer (Header_Size + I) := 0;
         end loop;
         for I in Data'Range loop
            P.Buffer (Header_Size + (I - Data'First)) := Data (I);
         end loop;
         Set_Used (P, Data'Length);
      end if;
   end Set_Payload;

   function To_Stream (P : Page) return Ada.Streams.Stream_Element_Array is
      R : Ada.Streams.Stream_Element_Array (0 .. Ada.Streams.Stream_Element_Offset (Page_Size - 1));
   begin
      for I in P.Buffer'Range loop
         R (Ada.Streams.Stream_Element_Offset (I)) := Ada.Streams.Stream_Element (P.Buffer (I));
      end loop;
      return R;
   end To_Stream;

   function From_Stream (S : Ada.Streams.Stream_Element_Array) return Page is
      P : Page;
   begin
      P.Buffer := (others => 0);
      for I in 0 .. Page_Size - 1 loop
         P.Buffer (I) := Byte (S (S'First + Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      return P;
   end From_Stream;
end Database.Storage.Pages;
