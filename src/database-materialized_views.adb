with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
with Database.Values;
package body Database.Materialized_Views is
   use type Ada.Containers.Count_Type;

   overriding function "=" (Left, Right : Materialized_View_Definition) return Boolean is
   begin
      return Left.Id = Right.Id and then Left.Name = Right.Name;
   end "=";
   function Create
     (Name          : Wide_Wide_String;
      Query         : Database.Queries.Query;
      Storage_Table : Natural) return Materialized_View_Definition is
   begin
      return (Id => 0, Name => To_Unbounded_Wide_Wide_String (Name), Query => Query,
              Storage_Table => Storage_Table, Last_Refresh_Commit => 0);
   end Create;
   function Validate (View : Materialized_View_Definition) return Database.Status.Result is
   begin
      if Length (View.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "materialized view name must not be empty");
      elsif View.Storage_Table = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema,
           "materialized view storage table must be registered");
      end if;
      return Database.Status.Success;
   end Validate;
   function Refresh
     (Tx   : in out Database.Transactions.Transaction;
      View : in out Materialized_View_Definition;
      Rows : Row_Vectors.Vector) return Database.Status.Result is
      pragma Unreferenced (Rows);
   begin
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure (Database.Status.Read_Only_Transaction,
           "materialized view refresh requires a write transaction");
      end if;
      View.Last_Refresh_Commit := Natural (Database.Transactions.Snapshot_Version (Tx));
      return Validate (View);
   end Refresh;

   function Row_Has_Key
     (Row        : Database.Rows.Row;
      Key_Column : Natural;
      Key_Row    : Database.Rows.Row) return Boolean is
   begin
      return Key_Column < Database.Rows.Column_Count (Row)
        and then Key_Column < Database.Rows.Column_Count (Key_Row)
        and then Database.Values.Equal
          (Database.Rows.Get (Row, Key_Column),
           Database.Rows.Get (Key_Row, Key_Column));
   end Row_Has_Key;

   procedure Delete_Key
     (Rows       : in out Row_Vectors.Vector;
      Key_Row    : Database.Rows.Row;
      Key_Column : Natural) is
   begin
      if Rows.Length > 0 then
         for I in reverse 0 .. Natural (Rows.Length) - 1 loop
            if Row_Has_Key (Rows.Element (I), Key_Column, Key_Row) then
               Rows.Delete (I);
            end if;
         end loop;
      end if;
   end Delete_Key;

   procedure Upsert_Row
     (Rows       : in out Row_Vectors.Vector;
      Row        : Database.Rows.Row;
      Key_Column : Natural) is
   begin
      if Rows.Length > 0 then
         for I in 0 .. Natural (Rows.Length) - 1 loop
            if Row_Has_Key (Rows.Element (I), Key_Column, Row) then
               Rows.Replace_Element (I, Row);
               return;
            end if;
         end loop;
      end if;
      Rows.Append (Row);
   end Upsert_Row;

   function Refresh_Incremental
     (Tx           : in out Database.Transactions.Transaction;
      View         : in out Materialized_View_Definition;
      Current_Rows : Row_Vectors.Vector;
      Inserted     : Row_Vectors.Vector;
      Updated      : Row_Vectors.Vector;
      Deleted_Rows : Row_Vectors.Vector;
      Key_Column   : Natural;
      Result       : out Row_Vectors.Vector) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      Result.Clear;
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure (Database.Status.Read_Only_Transaction,
           "incremental materialized view refresh requires a write transaction");
      end if;
      R := Validate (View);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      Result := Current_Rows;
      for Row of Deleted_Rows loop
         if Key_Column >= Database.Rows.Column_Count (Row) then
            return Database.Status.Failure
              (Database.Status.Invalid_Argument,
               "materialized view delete key column is outside row");
         end if;
         Delete_Key (Result, Row, Key_Column);
      end loop;
      for Row of Updated loop
         if Key_Column >= Database.Rows.Column_Count (Row) then
            return Database.Status.Failure
              (Database.Status.Invalid_Argument,
               "materialized view update key column is outside row");
         end if;
         Upsert_Row (Result, Row, Key_Column);
      end loop;
      for Row of Inserted loop
         if Key_Column >= Database.Rows.Column_Count (Row) then
            return Database.Status.Failure
              (Database.Status.Invalid_Argument,
               "materialized view insert key column is outside row");
         end if;
         Upsert_Row (Result, Row, Key_Column);
      end loop;
      View.Last_Refresh_Commit := Natural (Database.Transactions.Snapshot_Version (Tx));
      return Database.Status.Success;
   end Refresh_Incremental;
end Database.Materialized_Views;
