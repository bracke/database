--  Query optimizer statistics facade.
with Database.Diagnostics;
with Database.Indexes;
with Database.Schema;
with Database.Status;
with Database.Transactions;

--  Public specification for this database subsystem.
package Database.Statistics is
   --  Table_Statistic stores the public fields for this database abstraction.
   type Table_Statistic is record
      Row_Count  : Natural := 0;
      Page_Count : Natural := 0;
   end record;

   --  Index_Statistic stores the public fields for this database abstraction.
   type Index_Statistic is record
      Entry_Count : Natural := 0;
      Page_Count  : Natural := 0;
      Depth       : Natural := 0;
      Unique      : Boolean := False;
   end record;

   --  Return table stats for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Result produced by the function.
   function Table_Stats
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Table_Statistic;

   --  Return index stats for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Index_Stats
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema;
      Index  : Database.Indexes.Index_Metadata) return Index_Statistic;

   --  Return analyze for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Analyze
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result;

   --  Return analyze table for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Table_Name table name argument supplied to the operation.
   --  @return Result produced by the function.
   function Analyze_Table
     (Tx         : in out Database.Transactions.Transaction;
      Table_Name : Wide_Wide_String) return Database.Status.Result;
end Database.Statistics;
