with Database.Status;
with Ada.Streams;
with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Metrics;
with Database.Randomized;
with Database.Storage.Pages;
with Database.Storage.Record_Format;
with Database.Schema;
with Database.Rows;
with Database.Types;
with Database.Backup_Format;
with Database.Crypto_Checks;
with Database.Keys;
with Database.Crypto;
with Database.WAL;
with Database.Transactions;
with Database.Invariant_Checks;
with Database.Full_Text.Storage;
with Database.Full_Text.Postings;
with Database.Import;

package body Database.Fuzzing is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   procedure Delete_If_Exists (Path : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Path)) then
         Ada.Directories.Delete_File (Native (Path));
      end if;
   exception
      when others => null;
   end Delete_If_Exists;

   function Reject (Message : Wide_Wide_String) return Fuzz_Result is
   begin
      Database.Metrics.Increment_Fuzzing_Failures;
      return
        (Status => Database.Status.Failure (Database.Status.Corruption_Detected, Message),
         Inputs_Tested => 1,
         Inputs_Rejected => 1,
         Inputs_Accepted => 0,
         Max_Input_Length_Observed => 0,
         Minimal_Rejected_Length => Natural'Last);
   end Reject;

   function Accepted_Result return Fuzz_Result is
   begin
      return
        (Status => Database.Status.Success,
         Inputs_Tested => 1,
         Inputs_Rejected => 0,
         Inputs_Accepted => 1,
         Max_Input_Length_Observed => 0,
         Minimal_Rejected_Length => Natural'Last);
   end Accepted_Result;

   function Validate_Page_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
   begin
      if Data'Length /= Database.Storage.Pages.Page_Size then
         return Reject ("malformed page size rejected");
      end if;

      declare
         P : constant Database.Storage.Pages.Page := Database.Storage.Pages.From_Stream (Data);
         R : constant Database.Status.Result := Database.Storage.Pages.Validate
           (P, Database.Storage.Pages.Get_Id (P), Database.Storage.Pages.Get_Kind (P));
      begin
         if Database.Status.Is_Ok (R) then
            return Accepted_Result;
         else
            return Reject ("malformed page rejected by page validator");
         end if;
      end;
   exception
      when others => return Reject ("malformed page rejected without propagation");
   end Validate_Page_Input;

   function Validate_WAL_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      Path : constant Wide_Wide_String := "fuzz_wal.db";
      WPath : constant Wide_Wide_String := Database.WAL.WAL_Path (Path);
      File : Ada.Streams.Stream_IO.File_Type;
      R : Database.Status.Result;
   begin
      Delete_If_Exists (WPath);
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Native (WPath));
      if Data'Length > 0 then
         Ada.Streams.Stream_IO.Write (File, Data);
      end if;
      Ada.Streams.Stream_IO.Close (File);
      R := Database.WAL.Validate (Path);
      Delete_If_Exists (WPath);
      if Database.Status.Is_Ok (R) then
         if Data'Length = 0 then
            return Accepted_Result;
         else
            return Reject ("non-empty malformed WAL unexpectedly reached safe truncation boundary");
         end if;
      end if;
      return Reject ("malformed WAL rejected by WAL validator");
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception when others => null;
         end;
         Delete_If_Exists (WPath);
         return Reject ("malformed WAL rejected without propagation");
   end Validate_WAL_Input;

   function Validate_Record_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      S : Database.Schema.Table_Schema;
      Bytes : Database.Storage.Pages.Byte_Array (0 .. Database.Storage.Pages.Payload_Capacity - 1) := (others => 0);
      Row : Database.Rows.Row;
      R : Database.Status.Result;
   begin
      Database.Schema.Add_Column (S, "id", Database.Types.Integer_Value, Nullable => False, Primary_Key => True);
      for I in Data'Range loop
         exit when Natural (I - Data'First) > Bytes'Last;
         Bytes (Natural (I - Data'First)) := Database.Storage.Pages.Byte (Data (I));
      end loop;
      R := Database.Storage.Record_Format.Deserialize (S, Bytes, Row);
      if Database.Status.Is_Ok (R) then
         return Accepted_Result;
      end if;
      return Reject ("malformed record rejected by record decoder");
   exception
      when others =>
         return Reject ("malformed record rejected without propagation");
   end Validate_Record_Input;

   function Validate_Backup_Manifest_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      Dir : constant Wide_Wide_String := "fuzz_manifest";
      Manifest_Path : constant Wide_Wide_String := Database.Backup_Format.Manifest_Path (Dir);
      File : Ada.Streams.Stream_IO.File_Type;
      M : Database.Backup_Format.Manifest;
      R : Database.Status.Result;
   begin
      if not Ada.Directories.Exists (Native (Dir)) then
         Ada.Directories.Create_Path (Native (Dir));
      end if;
      Delete_If_Exists (Manifest_Path);
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Native (Manifest_Path));
      if Data'Length > 0 then
         Ada.Streams.Stream_IO.Write (File, Data);
      end if;
      Ada.Streams.Stream_IO.Close (File);
      R := Database.Backup_Format.Read_Manifest (Dir, M);
      if Database.Status.Is_Ok (R) then
         R := Database.Backup_Format.Validate_Manifest (Dir, M);
      end if;
      Delete_If_Exists (Manifest_Path);
      if Ada.Directories.Exists (Native (Dir)) then
         Ada.Directories.Delete_Directory (Native (Dir));
      end if;
      if Database.Status.Is_Ok (R) then
         return Accepted_Result;
      end if;
      return Reject ("malformed backup manifest rejected by manifest parser");
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception when others => null;
         end;
         Delete_If_Exists (Manifest_Path);
         begin
            if Ada.Directories.Exists (Native (Dir)) then
               Ada.Directories.Delete_Directory (Native (Dir));
            end if;
         exception when others => null;
         end;
         return Reject ("malformed backup manifest rejected without propagation");
   end Validate_Backup_Manifest_Input;

   function Validate_Encryption_Metadata_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      Key : Database.Keys.Encryption_Key := Database.Keys.Derive_Key ("fuzz key", Database.Keys.Default_Salt);
      Nonce : Database.Crypto.Nonce := (others => 0);
      Associated : Database.Crypto.Byte_Array (0 .. 0) := (others => 0);
      Cipher : Database.Crypto.Byte_Array (0 .. 0) := (others => 0);
      Tag : Database.Crypto.Authentication_Tag := (others => 0);
      Check : Database.Crypto_Checks.Check_Result;
   begin
      if Data'Length >= Tag'Length then
         for I in Tag'Range loop
            Tag (I) := Database.Crypto.Byte (Data (Data'First + Ada.Streams.Stream_Element_Offset (I)));
         end loop;
      end if;
      Check := Database.Crypto_Checks.Verify_Authenticated_Buffer (Key, Nonce, Associated, Cipher, Tag);
      if Database.Status.Is_Ok (Check.Result) then
         return Accepted_Result;
      end if;
      return Reject ("malformed encryption metadata rejected by authentication check");
   exception
      when others =>
         return Reject ("malformed encryption metadata rejected without propagation");
   end Validate_Encryption_Metadata_Input;

   function Validate_Import_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      Source : constant Wide_Wide_String := "fuzz_import.native";
      DB_Path : constant Wide_Wide_String := "fuzz_import.db";
      File : Ada.Streams.Stream_IO.File_Type;
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      R : Database.Status.Result;
   begin
      Delete_If_Exists (Source);
      Delete_If_Exists (DB_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Native (Source));
      if Data'Length > 0 then
         Ada.Streams.Stream_IO.Write (File, Data);
      end if;
      Ada.Streams.Stream_IO.Close (File);
      Database.Create (DB, DB_Path);
      if not Database.Status.Is_Ok (Database.Last_Result (DB)) then
         Delete_If_Exists (Source);
         Delete_If_Exists (DB_Path);
         return Reject ("import fuzz destination could not be created");
      end if;
      Database.Transactions.Begin_Write (DB, Tx);
      R := Database.Import.Import_Database (Tx, Source);
      Database.Transactions.Rollback (Tx);
      Database.Close (DB);
      Delete_If_Exists (Source);
      Delete_If_Exists (DB_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));
      if Database.Status.Is_Ok (R) then
         return Accepted_Result;
      end if;
      return Reject ("malformed logical import rejected by import parser");
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception when others => null;
         end;
         Delete_If_Exists (Source);
         Delete_If_Exists (DB_Path);
         Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));
         return Reject ("malformed logical import rejected without propagation");
   end Validate_Import_Input;

   function Validate_Full_Text_Input (Data : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
      P : Database.Storage.Pages.Page;
      Term : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Root : Database.Storage.Pages.Page_Id;
      Postings : Database.Full_Text.Postings.Posting_Vectors.Vector;
      R1, R2 : Database.Status.Result;
   begin
      if Data'Length /= Database.Storage.Pages.Page_Size then
         return Reject ("malformed full-text page size rejected");
      end if;
      P := Database.Storage.Pages.From_Stream (Data);
      R1 := Database.Full_Text.Storage.Parse_Dictionary_Page (P, Term, Root);
      if Database.Status.Is_Ok (R1) then
         return Accepted_Result;
      end if;
      R2 := Database.Full_Text.Storage.Parse_Posting_Page (P, Term, Postings);
      if Database.Status.Is_Ok (R2) then
         return Accepted_Result;
      end if;
      return Reject ("malformed full-text structure rejected by native decoder");
   exception
      when others =>
         return Reject ("malformed full-text structure rejected without propagation");
   end Validate_Full_Text_Input;

   function Looks_Trivially_Valid
     (Target : Fuzz_Target;
      Data   : Ada.Streams.Stream_Element_Array) return Boolean is
   begin
      case Target is
         when Page_Parser => return False;
         when WAL_Replay_Parser => return False;
         when Record_Decoder => return False;
         when Import_Parser => return False;
         when Backup_Manifest_Parser => return False;
         when Encryption_Metadata_Parser => return False;
         when Full_Text_Structure_Parser => return Data'Length >= 4;
      end case;
   end Looks_Trivially_Valid;

   function Fuzz_Input
     (Target : Fuzz_Target;
      Data   : Ada.Streams.Stream_Element_Array) return Fuzz_Result is
   begin
      case Target is
         when Page_Parser =>
            return Validate_Page_Input (Data);
         when WAL_Replay_Parser =>
            return Validate_WAL_Input (Data);
         when Record_Decoder =>
            return Validate_Record_Input (Data);
         when Backup_Manifest_Parser =>
            return Validate_Backup_Manifest_Input (Data);
         when Encryption_Metadata_Parser =>
            return Validate_Encryption_Metadata_Input (Data);
         when Import_Parser =>
            return Validate_Import_Input (Data);
         when Full_Text_Structure_Parser =>
            return Validate_Full_Text_Input (Data);
      end case;
   end Fuzz_Input;

   procedure Merge (Total : in out Fuzz_Result; One : Fuzz_Result) is
      Len : constant Natural := One.Max_Input_Length_Observed;
   begin
      Total.Inputs_Tested := Total.Inputs_Tested + One.Inputs_Tested;
      Total.Inputs_Rejected := Total.Inputs_Rejected + One.Inputs_Rejected;
      Total.Inputs_Accepted := Total.Inputs_Accepted + One.Inputs_Accepted;
      if Len > Total.Max_Input_Length_Observed then
         Total.Max_Input_Length_Observed := Len;
      end if;
      if One.Minimal_Rejected_Length < Total.Minimal_Rejected_Length then
         Total.Minimal_Rejected_Length := One.Minimal_Rejected_Length;
      end if;
   end Merge;

   function With_Length (R : Fuzz_Result; Len : Natural) return Fuzz_Result is
      Copy : Fuzz_Result := R;
   begin
      Copy.Max_Input_Length_Observed := Len;
      if Copy.Inputs_Rejected > 0 and then Len < Copy.Minimal_Rejected_Length then
         Copy.Minimal_Rejected_Length := Len;
      end if;
      return Copy;
   end With_Length;

   function Random_Data
     (G   : in out Database.Randomized.Generator;
      Len : Natural) return Ada.Streams.Stream_Element_Array is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Len));
   begin
      for J in Data'Range loop
         Data (J) := Ada.Streams.Stream_Element (Database.Randomized.Next_Natural (G, 256));
      end loop;
      return Data;
   end Random_Data;

   function Seeded_Data (Seed : Natural; Len : Natural) return Ada.Streams.Stream_Element_Array is
      G : Database.Randomized.Generator;
   begin
      Database.Randomized.Reset (G, Seed);
      return Random_Data (G, Len);
   end Seeded_Data;

   function Boundary_Data
     (Target : Fuzz_Target;
      Case_No : Natural) return Ada.Streams.Stream_Element_Array is
   begin
      case Target is
         when Page_Parser =>
            case Case_No mod 6 is
               when 0 =>
                  return Seeded_Data (1, 0);
               when 1 =>
                  return Seeded_Data (2, Database.Storage.Pages.Page_Size - 1);
               when 2 =>
                  return Seeded_Data (3, Database.Storage.Pages.Page_Size + 1);
               when 3 =>
                  declare
                     P : Database.Storage.Pages.Page;
                  begin
                     Database.Storage.Pages.Initialize (P, 1, Database.Storage.Pages.Table_Heap_Page);
                     return Database.Storage.Pages.To_Stream (P);
                  end;
               when 4 =>
                  declare
                     P : Database.Storage.Pages.Page;
                     S : Ada.Streams.Stream_Element_Array
                       (0 .. Ada.Streams.Stream_Element_Offset
                               (Database.Storage.Pages.Page_Size - 1));
                  begin
                     Database.Storage.Pages.Initialize (P, 1, Database.Storage.Pages.Table_Heap_Page);
                     S := Database.Storage.Pages.To_Stream (P);
                     S (0) := 0;
                     return S;
                  end;
               when others =>
                  declare
                     P : Database.Storage.Pages.Page;
                     S : Ada.Streams.Stream_Element_Array
                       (0 .. Ada.Streams.Stream_Element_Offset
                               (Database.Storage.Pages.Page_Size - 1));
                  begin
                     Database.Storage.Pages.Initialize (P, 1, Database.Storage.Pages.Table_Heap_Page);
                     S := Database.Storage.Pages.To_Stream (P);
                     S (S'Last) := (if S (S'Last) = 0 then 1 else 0);
                     return S;
                  end;
            end case;
         when WAL_Replay_Parser =>
            case Case_No mod 5 is
               when 0 => return Seeded_Data (4, 0);
               when 1 => return Seeded_Data (5, 1);
               when 2 => return Seeded_Data (6, 39);
               when 3 => return Seeded_Data (7, 40);
               when others => return Seeded_Data (8, 4096);
            end case;
         when Record_Decoder =>
            case Case_No mod 5 is
               when 0 => return Seeded_Data (9, 0);
               when 1 => return Seeded_Data (10, 1);
               when 2 => return Seeded_Data (11, 8);
               when 3 => return Seeded_Data (12, Database.Storage.Pages.Payload_Capacity);
               when others => return Seeded_Data (13, Database.Storage.Pages.Payload_Capacity + 1);
            end case;
         when Import_Parser =>
            case Case_No mod 4 is
               when 0 => return Seeded_Data (14, 0);
               when 1 => return Seeded_Data (15, 6);
               when 2 => return Seeded_Data (16, 128);
               when others => return Seeded_Data (17, 2048);
            end case;
         when Backup_Manifest_Parser =>
            case Case_No mod 5 is
               when 0 => return Seeded_Data (18, 0);
               when 1 =>
                  declare
                     D : constant String := "DATABASE_BACKUP_MANIFEST 1";
                     R : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (D'Length));
                  begin
                     for I in D'Range loop
                        R (Ada.Streams.Stream_Element_Offset (I))  :=
                          Ada.Streams.Stream_Element (Character'Pos (D (I)));
                     end loop;
                     return R;
                  end;
               when 2 => return Seeded_Data (19, 32);
               when 3 => return Seeded_Data (20, 512);
               when others => return Seeded_Data (21, 4096);
            end case;
         when Encryption_Metadata_Parser =>
            case Case_No mod 5 is
               when 0 => return Seeded_Data (22, 0);
               when 1 => return Seeded_Data (23, 1);
               when 2 => return Seeded_Data (24, 16);
               when 3 => return Seeded_Data (25, 32);
               when others => return Seeded_Data (26, 128);
            end case;
         when Full_Text_Structure_Parser =>
            case Case_No mod 6 is
               when 0 => return Seeded_Data (27, 0);
               when 1 => return Seeded_Data (28, Database.Storage.Pages.Page_Size - 1);
               when 2 => return Seeded_Data (29, Database.Storage.Pages.Page_Size + 1);
               when 3 =>
                  declare
                     P : Database.Storage.Pages.Page := Database.Full_Text.Storage.Build_Dictionary_Page (1,
                       "term", 2);
                  begin
                     return Database.Storage.Pages.To_Stream (P);
                  end;
               when 4 =>
                  declare
                     P : Database.Storage.Pages.Page := Database.Full_Text.Storage.Build_Dictionary_Page (1,
                       "term", 2);
                     S : Ada.Streams.Stream_Element_Array
                       (0 .. Ada.Streams.Stream_Element_Offset
                               (Database.Storage.Pages.Page_Size - 1));
                  begin
                     S := Database.Storage.Pages.To_Stream (P);
                     S (100) := (if S (100) = 0 then 1 else 0);
                     return S;
                  end;
               when others => return Seeded_Data (30, 4096);
            end case;
      end case;
   end Boundary_Data;

   function Mutate
     (Data : Ada.Streams.Stream_Element_Array;
      Mode : Natural) return Ada.Streams.Stream_Element_Array is
      Len : constant Natural := Data'Length;
   begin
      case Mode mod 5 is
         when 0 =>
            declare
               R : Ada.Streams.Stream_Element_Array (Data'Range) := Data;
            begin
               if R'Length > 0 then
                  R (R'First) := (if R (R'First) = 0 then 255 else 0);
               end if;
               return R;
            end;
         when 1 =>
            declare
               New_Len : constant Natural := Len / 2;
               R : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (New_Len));
            begin
               for I in R'Range loop
                  R (I) := Data (Data'First + (I - R'First));
               end loop;
               return R;
            end;
         when 2 =>
            declare
               New_Len : constant Natural := Len + 4;
               R : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (New_Len));
            begin
               for I in R'Range loop
                  if Natural (I - R'First) < Len then
                     R (I) := Data (Data'First + (I - R'First));
                  else
                     R (I) := Ada.Streams.Stream_Element ((Natural (I) * 37) mod 256);
                  end if;
               end loop;
               return R;
            end;
         when 3 =>
            declare
               R : Ada.Streams.Stream_Element_Array (Data'Range) := Data;
            begin
               if R'Length > 2 then
                  R (R'First + Ada.Streams.Stream_Element_Offset (R'Length / 2)) := (if R (R'First
                    + Ada.Streams.Stream_Element_Offset (R'Length / 2)) = 0 then 127 else 0);
               end if;
               return R;
            end;
         when others =>
            declare
               R : Ada.Streams.Stream_Element_Array (Data'Range) := Data;
            begin
               if R'Length > 0 then
                  R (R'Last) := (if R (R'Last) = 0 then 1 else 0);
               end if;
               return R;
            end;
      end case;
   end Mutate;

   function Length_Bound (Options : Fuzz_Options) return Positive is
   begin
      if Options.Max_Input_Length = 0 then
         return 1;
      else
         return Positive (Natural'Min (Options.Max_Input_Length, 4096)) + 1;
      end if;
   end Length_Bound;

   procedure Finalize_Corpus_Result (R : in out Fuzz_Result) is
   begin
      if R.Minimal_Rejected_Length = Natural'Last then
         R.Minimal_Rejected_Length := 0;
      end if;
      if R.Inputs_Rejected > 0 then
         R.Status := Database.Status.Failure
           (Database.Status.Fuzzing_Failure, "fuzzing rejected malformed inputs safely");
      else
         R.Status := Database.Status.Success;
      end if;
   end Finalize_Corpus_Result;

   function Fuzz_Deterministic
     (Target : Fuzz_Target;
      Seed   : Natural;
      Count  : Natural) return Fuzz_Result is
   begin
      return Fuzz_Deterministic (Target, Seed, Count, Default_Fuzz_Options);
   end Fuzz_Deterministic;

   function Fuzz_Deterministic
     (Target  : Fuzz_Target;
      Seed    : Natural;
      Count   : Natural;
      Options : Fuzz_Options) return Fuzz_Result is
      G : Database.Randomized.Generator;
      Total : Fuzz_Result;
   begin
      Database.Randomized.Reset (G, Seed);
      for I in 1 .. Count loop
         declare
            Bound : constant Positive := Length_Bound (Options);
            Len : constant Natural := Database.Randomized.Next_Natural (G, Bound);
            Data : constant Ada.Streams.Stream_Element_Array := Random_Data (G, Len);
            One : constant Fuzz_Result := With_Length (Fuzz_Input (Target, Data), Len);
         begin
            Merge (Total, One);
            exit when Options.Stop_On_First_Unexpected_Acceptance and then Database.Status.Is_Ok (One.Status);
         end;
      end loop;
      Finalize_Corpus_Result (Total);
      return Total;
   end Fuzz_Deterministic;

   function Fuzz_Corpus
     (Target  : Fuzz_Target;
      Seed    : Natural;
      Count   : Natural;
      Options : Fuzz_Options := Default_Fuzz_Options) return Fuzz_Result is
      G : Database.Randomized.Generator;
      Total : Fuzz_Result;
      Boundary_Count : constant Natural := 8;
   begin
      Database.Randomized.Reset (G, Seed);

      if Options.Include_Boundary_Cases then
         for Case_No in 0 .. Boundary_Count - 1 loop
            declare
               Data : constant Ada.Streams.Stream_Element_Array := Boundary_Data (Target, Case_No);
            begin
               if Data'Length <= Options.Max_Input_Length then
                  Merge (Total, With_Length (Fuzz_Input (Target, Data), Data'Length));
                  if Options.Include_Mutations then
                     for Mode in 0 .. 4 loop
                        declare
                           M : constant Ada.Streams.Stream_Element_Array := Mutate (Data, Mode);
                        begin
                           if M'Length <= Options.Max_Input_Length then
                              Merge (Total, With_Length (Fuzz_Input (Target, M), M'Length));
                           end if;
                        end;
                     end loop;
                  end if;
               end if;
            end;
         end loop;
      end if;

      for I in 1 .. Count loop
         declare
            Bound : constant Positive := Length_Bound (Options);
            Len : constant Natural := Database.Randomized.Next_Natural (G, Bound);
            Data : constant Ada.Streams.Stream_Element_Array := Random_Data (G, Len);
         begin
            Merge (Total, With_Length (Fuzz_Input (Target, Data), Len));
            if Options.Include_Mutations then
               declare
                  M : constant Ada.Streams.Stream_Element_Array := Mutate (Data, I);
               begin
                  if M'Length <= Options.Max_Input_Length then
                     Merge (Total, With_Length (Fuzz_Input (Target, M), M'Length));
                  end if;
               end;
            end if;
         end;
      end loop;

      Finalize_Corpus_Result (Total);
      return Total;
   end Fuzz_Corpus;

   function Fuzz_All_Targets
     (Seed    : Natural;
      Count_Per_Target : Natural;
      Options : Fuzz_Options := Default_Fuzz_Options) return Fuzz_Result is
      Total : Fuzz_Result;
   begin
      for T in Fuzz_Target loop
         Merge (Total, Fuzz_Corpus (T, Seed + Fuzz_Target'Pos (T), Count_Per_Target, Options));
      end loop;
      Finalize_Corpus_Result (Total);
      return Total;
   end Fuzz_All_Targets;
end Database.Fuzzing;
