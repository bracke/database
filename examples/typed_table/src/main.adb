with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Wide_Wide_Text_IO;

with Database;
with Database.Status;
with Database.Types;
with Database.Values;
with Database.Rows;
with Database.Schema;
with Database.Transactions;
with Database.Tables;
with Database.Predicates;

procedure Main is
   use Ada.Strings.Wide_Wide_Unbounded;

   type User_Id is new Natural;

   type User is record
      Id     : User_Id;
      Name   : Unbounded_Wide_Wide_String;
      Active : Boolean;
   end record;

   function To_Row (Item : User) return Database.Rows.Row;
   function From_Row (Row : Database.Rows.Row) return User;
   function Key_Of (Item : User) return User_Id;
   function Key_Value (Key : User_Id) return Database.Values.Value;

   function To_Row (Item : User) return Database.Rows.Row is
      Result : Database.Rows.Row;
   begin
      --  The database stores typed values, not the Ada record memory layout.
      Database.Rows.Append
        (Result,
         Database.Values.From_Integer (Integer (Item.Id)));

      Database.Rows.Append
        (Result,
         Database.Values.From_Text (To_Wide_Wide_String (Item.Name)));

      Database.Rows.Append
        (Result,
         Database.Values.From_Boolean (Item.Active));

      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return User is
   begin
      return
        (Id     =>
           User_Id
             (Database.Rows.Get (Row, 0).Int),
         Name   =>
           Database.Rows.Get (Row, 1).Text,
         Active =>
           Database.Rows.Get (Row, 2).Bool);
   end From_Row;

   function Key_Of (Item : User) return User_Id is
   begin
      return Item.Id;
   end Key_Of;

   function Key_Value (Key : User_Id) return Database.Values.Value is
   begin
      return Database.Values.From_Integer (Integer (Key));
   end Key_Value;

   package User_Tables is new Database.Tables.Typed
     (Row_Type     => User,
      Key_Type     => User_Id,
      To_Row       => To_Row,
      From_Row     => From_Row,
      Key_Of       => Key_Of,
      Key_Value    => Key_Value);

   function User_Schema return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      --  Public text APIs use Wide_Wide_String.
      --
      --  The exact constructor names are provided by Database.Schema and
      --  Database.Types. This example keeps the schema construction explicit so
      --  users can see the intended shape:
      --
      --    id      integer, primary key, not null
      --    name    Unicode text, not null
      --    active  Boolean, not null

      Result.Name := To_Unbounded_Wide_Wide_String ("users");

      Database.Schema.Add_Column
        (Result,
         Name        => "id",
         Kind        => Database.Types.Integer_Value,
         Nullable    => False,
         Primary_Key => True);

      Database.Schema.Add_Column
        (Result,
         Name        => "name",
         Kind        => Database.Types.Text_Value,
         Nullable    => False);

      Database.Schema.Add_Column
        (Result,
         Name        => "active",
         Kind        => Database.Types.Boolean_Value,
         Nullable    => False);

      return Result;
   end User_Schema;

   DB     : Database.Handle;
   Schema : Database.Schema.Table_Schema := User_Schema;
   Tx     : Database.Transactions.Transaction;
   Status : Database.Status.Result;

   Ada_User : constant User :=
     (Id     => 1,
      Name   => To_Unbounded_Wide_Wide_String ("Ada Lovelace"),
      Active => True);

   Updated_User : constant User :=
     (Id     => 1,
      Name   => To_Unbounded_Wide_Wide_String ("Ada"),
      Active => True);

begin
   --  Open or create the database.
   --
   --  For an in-memory example, use the in-memory open/create helper exposed by
   --  Database. For durable storage, use the persistent open/create API.
   Database.Open_In_Memory (DB);

   if not Database.Last_Operation_Succeeded (DB) then
      Ada.Wide_Wide_Text_IO.Put_Line ("failed to create database");
      return;
   end if;

   --  Register a typed table. Registration validates schema compatibility.
   Status := User_Tables.Register (DB => DB, Schema => Schema);

   if not Database.Status.Is_Ok (Status) then
      Ada.Wide_Wide_Text_IO.Put_Line ("failed to register users table");
      return;
   end if;

   --  All reads and writes go through a transaction object.
   Database.Transactions.Begin_Write (DB, Tx);

   Status := User_Tables.Insert (Tx, DB, Schema, Ada_User);
   if not Database.Status.Is_Ok (Status) then
      Database.Transactions.Rollback (Tx);
      Ada.Wide_Wide_Text_IO.Put_Line ("insert failed");
      return;
   end if;

   declare
      Found : User;
   begin
      Status := User_Tables.Find (Tx, DB, Schema, 1, Found);
      if Database.Status.Is_Ok (Status) then
         Ada.Wide_Wide_Text_IO.Put_Line
           ("found user: " &
            To_Wide_Wide_String (Found.Name));
      end if;
   end;

   Status := User_Tables.Update (Tx, DB, Schema, Updated_User);
   if not Database.Status.Is_Ok (Status) then
      Database.Transactions.Rollback (Tx);
      Ada.Wide_Wide_Text_IO.Put_Line ("update failed");
      return;
   end if;

   --  Predicate-based filtering. This is not SQL.
   declare
      Active_Only : constant Database.Predicates.Predicate :=
        Database.Predicates.Column_Equals
          (Index => 2,
           Value => Database.Values.From_Boolean (True));

      Cursor : User_Tables.Cursor;
   begin
      Status := User_Tables.Scan (Tx, DB, Schema, Active_Only, Cursor);
      if Database.Status.Is_Ok (Status) then
         while User_Tables.Has_Element (Cursor) loop
            declare
               Item : constant User := User_Tables.Element (Cursor);
            begin
               Ada.Wide_Wide_Text_IO.Put_Line
                 ("active user: " & To_Wide_Wide_String (Item.Name));
            end;
            Status := User_Tables.Next (Tx, DB, Schema, Active_Only, Cursor);
            exit when not Database.Status.Is_Ok (Status);
         end loop;
      end if;
   end;

   Status := User_Tables.Delete (Tx, DB, Schema, 1);
   if not Database.Status.Is_Ok (Status) then
      Database.Transactions.Rollback (Tx);
      Ada.Wide_Wide_Text_IO.Put_Line ("delete failed");
      return;
   end if;

   Database.Transactions.Commit (Tx);
   Ada.Wide_Wide_Text_IO.Put_Line ("typed table example complete");
end Main;
