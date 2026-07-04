--  Explicit transaction-scoped schema evolution operations.
with Database.Status;
with Database.Transactions;
with Database.Types;
with Database.Values;

   --  Public nested package `Database.Migrations`.
package Database.Migrations is
   --  Add a column. If Default_Value is Null, the new column is nullable.
   --  If Default_Value is non-null, the new column is non-null. This preserves
   --  the convenience API while keeping migrations explicit.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Column_Name column name argument supplied to the operation.
   --  @param Type_Info type info argument supplied to the operation.
   --  @param Default_Value default value argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Column
     (Tx            : in out Database.Transactions.Transaction;
      Table_Name    : Wide_Wide_String;
      Column_Name   : Wide_Wide_String;
      Type_Info     : Database.Types.Type_Descriptor;
      Default_Value : Database.Values.Value) return Database.Status.Result;

   --  Add a column with explicit nullability. This is needed when a nullable
   --  column should still receive a non-null default in existing rows.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Column_Name column name argument supplied to the operation.
   --  @param Type_Info type info argument supplied to the operation.
   --  @param Nullable nullable argument supplied to the operation.
   --  @param Default_Value default value argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Column
     (Tx            : in out Database.Transactions.Transaction;
      Table_Name    : Wide_Wide_String;
      Column_Name   : Wide_Wide_String;
      Type_Info     : Database.Types.Type_Descriptor;
      Nullable      : Boolean;
      Default_Value : Database.Values.Value) return Database.Status.Result;

   --  Public operation `Rename_Column`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Old_Name old name argument supplied to the operation.
   --  @param New_Name new name argument supplied to the operation.
   --  @return Result produced by the function.
   function Rename_Column
     (Tx         : in out Database.Transactions.Transaction;
      Table_Name : Wide_Wide_String;
      Old_Name   : Wide_Wide_String;
      New_Name   : Wide_Wide_String) return Database.Status.Result;

   --  Public operation `Drop_Column`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Column_Name column name argument supplied to the operation.
   --  @return Result produced by the function.
   function Drop_Column
     (Tx          : in out Database.Transactions.Transaction;
      Table_Name  : Wide_Wide_String;
      Column_Name : Wide_Wide_String) return Database.Status.Result;

   --  Public operation `Change_Nullability`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Column_Name column name argument supplied to the operation.
   --  @param Nullable nullable argument supplied to the operation.
   --  @return Result produced by the function.
   function Change_Nullability
     (Tx          : in out Database.Transactions.Transaction;
      Table_Name  : Wide_Wide_String;
      Column_Name : Wide_Wide_String;
      Nullable    : Boolean) return Database.Status.Result;

   procedure Commit_Transaction (Transaction_Id : Natural);
   procedure Rollback_Transaction (Transaction_Id : Natural; DB : in out Database.Handle);
end Database.Migrations;
