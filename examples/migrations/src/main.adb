with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Migrations;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

procedure Main is
   use Ada.Strings.Wide_Wide_Unbounded;
   type Person is record Id : Integer; Name : Wide_Wide_String (1 .. 16); end record;
   function To_Row (P : Person) return Database.Rows.Row is R : Database.Rows.Row; begin
      Database.Rows.Append (R, Database.Values.From_Integer (P.Id)); Database.Rows.Append (R, Database.Values.From_Text (P.Name)); return R; end To_Row;
   function From_Row (R : Database.Rows.Row) return Person is
      S : constant Wide_Wide_String := To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      P : Person := (Database.Rows.Get (R, 0).Int, (others => ' '));
   begin for I in 1 .. Integer'Min (16, S'Length) loop P.Name (I) := S (S'First + I - 1); end loop; return P; end From_Row;
   function Key_Of (P : Person) return Integer is (P.Id);
   function Key_Value (K : Integer) return Database.Values.Value is (Database.Values.From_Integer (K));
   package People is new Database.Tables.Typed (Person, Integer, To_Row, From_Row, Key_Of, Key_Value);
   DB : Database.Handle; Tx : Database.Transactions.Transaction; S : Database.Schema.Table_Schema; R : Database.Status.Result;
begin
   Database.Open_In_Memory (DB);
   S.Name := To_Unbounded_Wide_Wide_String ("people");
   Database.Schema.Add_Column (S, "id", Database.Types.Integer_Value, False, True);
   Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
   R := People.Register (DB, S); pragma Assert (Database.Status.Is_Ok (R), "register failed");
   Database.Transactions.Begin_Write (DB, Tx);
   R := People.Insert (Tx, DB, S, (1, "Ada             ")); pragma Assert (Database.Status.Is_Ok (R), "insert failed");
   R := Database.Migrations.Add_Column
     (Tx, "people", "age", Database.Types.Describe (Database.Types.Integer_Value), True, Database.Values.Null_Value);
   pragma Assert (Database.Status.Is_Ok (R), "add-column migration failed");
   R := Database.Transactions.Commit (Tx); pragma Assert (Database.Status.Is_Ok (R), "migration commit failed");
   Database.Close (DB);
end Main;
