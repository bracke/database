--  Structured in-process tracing for operational diagnostics.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;

--  Structured tracing support.
package Database.Tracing is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Trace_Category defines a public database type used by this package.
   type Trace_Category is
     (Transaction_Trace,
      WAL_Trace,
      Query_Trace,
      Storage_Trace,
      Optimizer_Trace,
      Locking_Trace,
      Backup_Trace,
      Encryption_Trace,
      Integrity_Trace,
      Extension_Trace);

   --  Timestamp_Type defines a public database type used by this package.
   subtype Timestamp_Type is Natural;

   --  Trace_Event stores the public fields for this database abstraction.
   type Trace_Event is record
      Timestamp : Timestamp_Type := 0;
      Category  : Trace_Category := Transaction_Trace;
      Message   : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Sensitive : Boolean := False;
   end record;

   --  Sink_Access defines a public database type used by this package.
   type Sink_Access is access procedure (Event : Trace_Event);

   --  Perform enable for the supplied database state or arguments.
   procedure Enable;
   --  Perform disable for the supplied database state or arguments.
   procedure Disable;
   --  Return is enabled for the supplied database state or arguments.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Enabled return Boolean;
   --  Perform enable category for the supplied database state or arguments.
   --  @param Category category argument supplied to the operation.
   procedure Enable_Category (Category : Trace_Category);
   --  Perform disable category for the supplied database state or arguments.
   --  @param Category category argument supplied to the operation.
   procedure Disable_Category (Category : Trace_Category);
   --  Return category enabled for the supplied database state or arguments.
   --  @param Category category argument supplied to the operation.
   --  @return Result produced by the function.
   function Category_Enabled (Category : Trace_Category) return Boolean;
   --  Perform enable sensitive traces for the supplied database state or arguments.
   procedure Enable_Sensitive_Traces;
   --  Perform disable sensitive traces for the supplied database state or arguments.
   procedure Disable_Sensitive_Traces;
   --  Return sensitive traces enabled for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Sensitive_Traces_Enabled return Boolean;

   --  Return emit trace for the supplied database state or arguments.
   --  @param Event event argument supplied to the operation.
   --  @return Result produced by the function.
   function Emit_Trace (Event : Trace_Event) return Database.Status.Result;
   --  Perform emit trace for the supplied database state or arguments.
   --  @param Event event argument supplied to the operation.
   procedure Emit_Trace (Event : Trace_Event);
   --  Return emit for the supplied database state or arguments.
   --  @param Category category argument supplied to the operation.
   --  @param Message message argument supplied to the operation.
   --  @param Sensitive sensitive argument supplied to the operation.
   --  @return Result produced by the function.
   function Emit
     (Category  : Trace_Category;
      Message   : Wide_Wide_String;
      Sensitive : Boolean := False) return Database.Status.Result;

   --  Perform enable console sink for the supplied database state or arguments.
   procedure Enable_Console_Sink;
   --  Perform disable console sink for the supplied database state or arguments.
   procedure Disable_Console_Sink;
   --  Return enable file sink for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Enable_File_Sink (Path : String) return Database.Status.Result;
   --  Perform disable file sink for the supplied database state or arguments.
   procedure Disable_File_Sink;
   --  Perform set custom sink for the supplied database state or arguments.
   --  @param Sink sink argument supplied to the operation.
   procedure Set_Custom_Sink (Sink : Sink_Access);
   --  Perform clear custom sink for the supplied database state or arguments.
   procedure Clear_Custom_Sink;
   --  Perform clear buffer for the supplied database state or arguments.
   procedure Clear_Buffer;
   --  Return buffered count for the supplied database state or arguments.
   --  @return Number of items represented by the queried object.
   function Buffered_Count return Natural;
   --  Return buffered event for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Buffered_Event (Index : Natural) return Trace_Event;
   --  Perform reset for the supplied database state or arguments.
   procedure Reset;
end Database.Tracing;
