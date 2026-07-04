--  Rule-based optimizer for Ada-native logical query plans.
with Database.Execution_Plans;
with Database.Plans;
with Database.Transactions;

--  Query optimization and plan selection.
package Database.Optimizer is
   --  Optimizer_Settings stores the public fields for this database abstraction.
   type Optimizer_Settings is record
      Enabled         : Boolean := True;
      Force_Heap_Scan : Boolean := False;
   end record;

   --  Return default settings for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Default_Settings return Optimizer_Settings;

   --  Return optimize for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Plan plan argument supplied to the operation.
   --  @param Settings settings argument supplied to the operation.
   --  @return Result produced by the function.
   function Optimize
     (Tx       : in out Database.Transactions.Transaction;
      Plan     : Database.Plans.Logical_Plan;
      Settings : Optimizer_Settings := Default_Settings)
      return Database.Execution_Plans.Physical_Plan_Result;
end Database.Optimizer;
