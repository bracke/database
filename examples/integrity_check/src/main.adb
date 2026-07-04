with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Check;
with Database.Diagnostics;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Rows;

procedure Main is
   use Ada.Strings.Wide_Wide_Unbounded;
   type Item is record Id : Integer; Name : Wide_Wide_String (1 .. 8); end record;
   function To_Row (I : Item) return Database.Rows.Row is R : Database.Rows.Row; begin
      Database.Rows.Append (R, Database.Values.From_Integer (I.Id)); Database.Rows.Append (R, Database.Values.From_Text (I.Name)); return R; end To_Row;
   function From_Row (R : Database.Rows.Row) return Item is
      S : constant Wide_Wide_String := To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      I : Item := (Database.Rows.Get (R, 0).Int, (others => ' '));
   begin for N in 1 .. Integer'Min (8, S'Length) loop I.Name (N) := S (S'First + N - 1); end loop; return I; end From_Row;
   function Key_Of (I : Item) return Integer is (I.Id);
   function Key_Value (K : Integer) return Database.Values.Value is (Database.Values.From_Integer (K));
   package Items is new Database.Tables.Typed (Item, Integer, To_Row, From_Row, Key_Of, Key_Value);
   DB : Database.Handle; Tx : Database.Transactions.Transaction; S : Database.Schema.Table_Schema; R : Database.Status.Result; Check : Database.Check.Check_Result;
begin
   Database.Open_In_Memory (DB);
   S.Name := To_Unbounded_Wide_Wide_String ("items");
   Database.Schema.Add_Column (S, "id", Database.Types.Integer_Value, False, True);
   Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
   R := Items.Register (DB, S); pragma Assert (Database.Status.Is_Ok (R), "register failed");
   Database.Transactions.Begin_Read (DB, Tx);
   Check := Database.Check.Check_Database (Tx);
   pragma Assert (Check.Success, "integrity check failed");
   pragma Assert (Database.Diagnostics.Page_Count (Tx) >= 0, "diagnostic page count invalid");
   R := Database.Transactions.Commit (Tx); pragma Assert (Database.Status.Is_Ok (R), "commit failed");
   Database.Close (DB);
end Main;
