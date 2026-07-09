with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Catalog;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

procedure Main is
   use Ada.Strings.Wide_Wide_Unbounded;
   type User is record Id : Integer; Name : Wide_Wide_String (1 .. 16); Age : Integer; end record;
   function To_Row (U : User) return Database.Rows.Row is R : Database.Rows.Row; begin
      Database.Rows.Append (R, Database.Values.From_Integer (U.Id));
      Database.Rows.Append (R, Database.Values.From_Text (U.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (U.Age)); return R; end To_Row;
   function From_Row (R : Database.Rows.Row) return User is
      S : constant Wide_Wide_String := To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      U : User := (Database.Rows.Get (R, 0).Int, (others => ' '), Database.Rows.Get (R, 2).Int);
   begin for I in 1 .. Integer'Min (16, S'Length) loop U.Name (I) := S (S'First + I - 1); end loop; return U; end From_Row;
   function Key_Of (U : User) return Integer is (U.Id);
   function Key_Value (K : Integer) return Database.Values.Value is (Database.Values.From_Integer (K));
   package Users is new Database.Tables.Typed (User, Integer, To_Row, From_Row, Key_Of, Key_Value);
   DB : Database.Handle; 
   Tx : Database.Transactions.Transaction; 
   S : Database.Schema.Table_Schema; 
   R : Database.Status.Result; U : User;
   Path : constant Wide_Wide_String := "example_persistent.database";
begin
   if Ada.Directories.Exists ("example_persistent.database") then Ada.Directories.Delete_File ("example_persistent.database"); end if;
   Database.Create (DB, Path); pragma Assert (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
   S.Name := To_Unbounded_Wide_Wide_String ("users");
   Database.Schema.Add_Column (S, "id", Database.Types.Integer_Value, False, True);
   Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
   Database.Schema.Add_Column (S, "age", Database.Types.Integer_Value, False);
   R := Users.Register (DB, S); pragma Assert (Database.Status.Is_Ok (R), "register failed");
   Database.Transactions.Begin_Write (DB, Tx);
   R := Users.Insert (Tx, DB, S, (1, "Ada             ", 42)); pragma Assert (Database.Status.Is_Ok (R), "insert failed");
   R := Database.Transactions.Commit (Tx); pragma Assert (Database.Status.Is_Ok (R), "commit failed");
   Database.Close (DB);

   Database.Open (DB, Path); pragma Assert (Database.Status.Is_Ok (Database.Last_Result (DB)), "open failed");
   R := Database.Catalog.Find_By_Name ("users", S); pragma Assert (Database.Status.Is_Ok (R), "catalog lookup failed");
   Database.Transactions.Begin_Read (DB, Tx);
   R := Users.Find (Tx, DB, S, 1, U); pragma Assert (Database.Status.Is_Ok (R), "find after reopen failed");
   R := Database.Transactions.Commit (Tx); pragma Assert (Database.Status.Is_Ok (R), "read commit failed");
   Database.Close (DB);
end Main;
