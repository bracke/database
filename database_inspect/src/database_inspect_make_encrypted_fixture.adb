with Ada.Characters.Conversions;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Wide_Wide_Text_IO;

with Database;
with Database.Keys;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

procedure Database_Inspect_Make_Encrypted_Fixture is
   use Ada.Command_Line;
   use Ada.Strings.Wide_Wide_Unbounded;

   Passphrase : constant Wide_Wide_String := "database-inspect-smoke";

   type Doc_Id is new Natural;

   type Doc is record
      Id   : Doc_Id;
      Text : Unbounded_Wide_Wide_String;
   end record;

   function To_Row (Item : Doc) return Database.Rows.Row;
   function From_Row (Row : Database.Rows.Row) return Doc;
   function Key_Of (Item : Doc) return Doc_Id;
   function Key_Value (Key : Doc_Id) return Database.Values.Value;

   function To_Row (Item : Doc) return Database.Rows.Row is
      Result : Database.Rows.Row;
   begin
      Database.Rows.Append
        (Result,
         Database.Values.From_Integer (Integer (Item.Id)));
      Database.Rows.Append
        (Result,
         Database.Values.From_Text (To_Wide_Wide_String (Item.Text)));
      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Doc is
   begin
      return
        (Id   => Doc_Id (Database.Rows.Get (Row, 0).Int),
         Text => Database.Rows.Get (Row, 1).Text);
   end From_Row;

   function Key_Of (Item : Doc) return Doc_Id is
   begin
      return Item.Id;
   end Key_Of;

   function Key_Value (Key : Doc_Id) return Database.Values.Value is
   begin
      return Database.Values.From_Integer (Integer (Key));
   end Key_Value;

   package Doc_Tables is new Database.Tables.Typed
     (Row_Type  => Doc,
      Key_Type  => Doc_Id,
      To_Row    => To_Row,
      From_Row  => From_Row,
      Key_Of    => Key_Of,
      Key_Value => Key_Value);

   function Doc_Schema return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String ("docs");
      Database.Schema.Add_Column
        (Result,
         Name        => "id",
         Kind        => Database.Types.Integer_Value,
         Nullable    => False,
         Primary_Key => True);
      Database.Schema.Add_Column
        (Result,
         Name     => "body",
         Kind     => Database.Types.Text_Value,
         Nullable => False);
      return Result;
   end Doc_Schema;

   function Arg (Index : Positive) return Wide_Wide_String is
   begin
      return Ada.Characters.Conversions.To_Wide_Wide_String (Argument (Index));
   end Arg;

   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   procedure Delete_If_Present (Path : Wide_Wide_String) is
      P : constant String := Native (Path);
   begin
      if Ada.Directories.Exists (P) then
         Ada.Directories.Delete_File (P);
      end if;
   end Delete_If_Present;

   procedure Delete_Previous_Artifacts (Path : Wide_Wide_String) is
   begin
      Delete_If_Present (Path);
      Delete_If_Present (Path & ".fts");
      Delete_If_Present (Path & ".wal");
      Delete_If_Present (Path & ".wal.enc");
      Delete_If_Present (Path & ".page0.enc");
      Delete_If_Present (Path & ".page1.enc");
   end Delete_Previous_Artifacts;

   DB   : Database.Handle;
   Key  : Database.Keys.Encryption_Key :=
     Database.Keys.Derive_Key (Passphrase, Database.Keys.Default_Salt);
   Path : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String :=
     Ada.Strings.Wide_Wide_Unbounded.Null_Unbounded_Wide_Wide_String;
   Schema : Database.Schema.Table_Schema := Doc_Schema;
   Tx     : Database.Transactions.Transaction;
   Status : Database.Status.Result;
begin
   if Argument_Count /= 1 then
      Ada.Wide_Wide_Text_IO.Put_Line
        (Ada.Wide_Wide_Text_IO.Standard_Error,
         "usage: database_inspect_make_encrypted_fixture <database>");
      Set_Exit_Status (Failure);
      Database.Keys.Clear (Key);
      return;
   end if;

   Path := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
     (Arg (1));
   Delete_Previous_Artifacts
     (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Path));
   Database.Create_Encrypted
     (DB, Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Path), Key);
   if not Database.Last_Operation_Succeeded (DB) then
      Ada.Wide_Wide_Text_IO.Put_Line
        (Ada.Wide_Wide_Text_IO.Standard_Error,
         "encrypted fixture create failed");
      Set_Exit_Status (Failure);
      Database.Keys.Clear (Key);
      return;
   end if;

   Status := Doc_Tables.Register (DB, Schema);
   if not Database.Status.Is_Ok (Status) then
      Ada.Wide_Wide_Text_IO.Put_Line
        (Ada.Wide_Wide_Text_IO.Standard_Error,
         "encrypted fixture schema register failed");
      Database.Close (DB);
      Set_Exit_Status (Failure);
      Database.Keys.Clear (Key);
      return;
   end if;

   Database.Transactions.Begin_Write (DB, Tx);
   Status := Doc_Tables.Insert
     (Tx,
      DB,
      Schema,
      (Id   => 501,
       Text => To_Unbounded_Wide_Wide_String ("encrypted inspector row")));
   if not Database.Status.Is_Ok (Status) then
      Database.Transactions.Rollback (Tx);
      Ada.Wide_Wide_Text_IO.Put_Line
        (Ada.Wide_Wide_Text_IO.Standard_Error,
         "encrypted fixture row insert failed");
      Database.Close (DB);
      Set_Exit_Status (Failure);
      Database.Keys.Clear (Key);
      return;
   end if;

   Status := Database.Transactions.Commit (Tx);
   if not Database.Status.Is_Ok (Status) then
      Ada.Wide_Wide_Text_IO.Put_Line
        (Ada.Wide_Wide_Text_IO.Standard_Error,
         "encrypted fixture commit failed");
      Database.Close (DB);
      Set_Exit_Status (Failure);
      Database.Keys.Clear (Key);
      return;
   end if;

   Database.Close (DB);
   Database.Keys.Clear (Key);
end Database_Inspect_Make_Encrypted_Fixture;
