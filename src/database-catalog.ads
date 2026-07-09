--  In-process catalog registry and persistent catalog save/load support.
with Database.Schema;
with Database.Status;
with Database.Rows;
with Database.Foreign_Keys;
with Database.Check_Constraints;
with Database.Generated_Columns;
with Database.Views;
with Database.Materialized_Views;
with Database.Full_Text.Indexes;

   --  Public nested package `Database.Catalog`.
package Database.Catalog is
   --  Selects the catalog registry owned by a database handle. Package-level
   --  lookup APIs operate on the selected handle registry for compatibility
   --  with earlier Ada-native APIs;
   --  operations that receive a Handle select
   --  automatically before reading or mutating catalog state.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);
   --  Perform drop database for the supplied database state or arguments.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);
   --  Public operation `Clear;
   --  `. See the package documentation for transaction, ownership, and error-result semantics.
   procedure Clear;
   --  Public operation `Register`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param DB database handle used by the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Status result describing whether the operation succeeded.
   function Register
     (DB     : in out Database.Handle;
      Schema : in out Database.Schema.Table_Schema) return Database.Status.Result;
   --  Public operation `Find_By_Name`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Name logical name of the object.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Requested value or optional value according to the package contract.
   function Find_By_Name
     (Name   : Wide_Wide_String;
      Schema : out Database.Schema.Table_Schema) return Database.Status.Result;
   --  Return find by id for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Requested value or optional value according to the package contract.
   function Find_By_Id
     (Table_Id : Natural;
      Schema   : out Database.Schema.Table_Schema) return Database.Status.Result;
   --  Public operation `Update_Table`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param DB database handle used by the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Status result describing whether the operation succeeded.
   function Update_Table
     (DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema) return Database.Status.Result;
   --  Update selected in-memory catalog state without immediately saving the
   --  catalog page. Transaction commit is responsible for durable save.
   function Stage_Update_Table
     (DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema) return Database.Status.Result;
   --  Public operation `Save`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Save (DB : in out Database.Handle) return Database.Status.Result;
   --  Public operation `Load`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Load (DB : in out Database.Handle) return Database.Status.Result;
   --  Public operation `Table_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @return Number of items represented by the queried object.
   function Table_Count return Natural;
   --  Public operation `Table_At`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Table_At (Index : Natural) return Database.Schema.Table_Schema;

   --  Return add foreign key for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Definition definition argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Foreign_Key
     (DB         : in out Database.Handle;
      Definition : Database.Foreign_Keys.Foreign_Key_Definition) return Database.Status.Result;
   --  Return foreign keys for referencing table for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @return Result produced by the function.
   function Foreign_Keys_For_Referencing_Table
     (Table_Id : Natural) return Database.Foreign_Keys.Foreign_Key_Vectors.Vector;
   --  Return foreign keys for referenced table for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @return Result produced by the function.
   function Foreign_Keys_For_Referenced_Table
     (Table_Id : Natural) return Database.Foreign_Keys.Foreign_Key_Vectors.Vector;

   --  Return add check constraint for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Constraint constraint argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Check_Constraint
     (DB         : in out Database.Handle;
      Table_Id   : Natural;
      Constraint : Database.Check_Constraints.Check_Constraint) return Database.Status.Result;
   --  Return check constraints for table for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @return Result produced by the function.
   function Check_Constraints_For_Table
     (Table_Id : Natural) return Database.Check_Constraints.Check_Constraint_Vectors.Vector;

   --  Return add generated column for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Column column argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Generated_Column
     (DB       : in out Database.Handle;
      Table_Id : Natural;
      Column   : Database.Generated_Columns.Generated_Column) return Database.Status.Result;
   --  Return generated columns for table for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @return Result produced by the function.
   function Generated_Columns_For_Table
     (Table_Id : Natural) return Database.Generated_Columns.Generated_Column_Vectors.Vector;

   --  Return add view for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param View view argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_View
     (DB   : in out Database.Handle;
      View : in out Database.Views.View_Definition) return Database.Status.Result;
   --  Return find view for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param View view argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Find_View
     (Name : Wide_Wide_String;
      View : out Database.Views.View_Definition) return Database.Status.Result;
   --  Return view count for the supplied database state or arguments.
   --  @return Number of items represented by the queried object.
   function View_Count return Natural;
   --  Return view at for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function View_At (Index : Natural) return Database.Views.View_Definition;
   --  Return update view for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param View view argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Update_View
     (DB   : in out Database.Handle;
      View : Database.Views.View_Definition) return Database.Status.Result;

   --  Return add materialized view for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param View view argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Materialized_View
     (DB   : in out Database.Handle;
      View : in out Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result;
   --  Return find materialized view for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param View view argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Find_Materialized_View
     (Name : Wide_Wide_String;
      View : out Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result;
   --  Return materialized view count for the supplied database state or arguments.
   --  @return Number of items represented by the queried object.
   function Materialized_View_Count return Natural;
   --  Return materialized view at for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Materialized_View_At
     (Index : Natural) return Database.Materialized_Views.Materialized_View_Definition;
   --  Return update materialized view for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param View view argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Update_Materialized_View
     (DB   : in out Database.Handle;
      View : Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result;

   --  Persistent full-text index definitions. Posting lists are rebuildable
   --  from table rows;
   --  definitions are catalog state and survive a missing
   --  or stale full-text sidecar cache.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Full_Text_Index
     (DB       : in out Database.Handle;
      Metadata : Database.Full_Text.Indexes.Full_Text_Index_Metadata) return Database.Status.Result;
   --  Return remove full text index for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Remove_Full_Text_Index
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result;
   --  Return full text index definitions for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Full_Text_Index_Definitions return Database.Full_Text.Indexes.Metadata_Vectors.Vector;

   --  Row registry used by Ada-native integrity checks for in-memory tables.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Register_Row (Table_Id : Natural; Row : Database.Rows.Row);
   --  Perform remove row for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Key_Row key row argument supplied to the operation.
   procedure Remove_Row (Table_Id : Natural; Schema : Database.Schema.Table_Schema; Key_Row : Database.Rows.Row);
   --  Perform replace row for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Old_Row old row argument supplied to the operation.
   --  @param New_Row new row argument supplied to the operation.
   procedure Replace_Row
     (Table_Id : Natural;
      Schema : Database.Schema.Table_Schema;
      Old_Row, New_Row : Database.Rows.Row);
   --  Return rows for table for the supplied database state or arguments.
   --  @param Table_Id table id argument supplied to the operation.
   --  @return Result produced by the function.
   function Rows_For_Table (Table_Id : Natural) return Database.Foreign_Keys.Row_Vectors.Vector;
end Database.Catalog;
