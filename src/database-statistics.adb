with Database.Status;

package body Database.Statistics is
   function Table_Stats
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Table_Statistic is
   begin
      return
        (Row_Count  => Database.Diagnostics.Table_Row_Count (Tx, Schema),
         Page_Count => Database.Diagnostics.Table_Page_Count (Tx, Schema));
   end Table_Stats;

   function Index_Stats
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema;
      Index  : Database.Indexes.Index_Metadata) return Index_Statistic is
   begin
      return
        (Entry_Count => Database.Diagnostics.Table_Row_Count (Tx, Schema),
         Page_Count  => Database.Diagnostics.Index_Page_Count (Tx, Index),
         Depth       => Database.Diagnostics.Index_Depth (Tx, Index),
         Unique      => Index.Unique);
   end Index_Stats;

   function Analyze
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result is
      pragma Unreferenced (Tx);
   begin
      --  The engine keeps exact statistics in existing table/index metadata and
      --  diagnostics counters. Analyze is a synchronization point for callers.
      return Database.Status.Success;
   end Analyze;

   function Analyze_Table
     (Tx         : in out Database.Transactions.Transaction;
      Table_Name : Wide_Wide_String) return Database.Status.Result is
      pragma Unreferenced (Tx, Table_Name);
   begin
      return Database.Status.Success;
   end Analyze_Table;
end Database.Statistics;
