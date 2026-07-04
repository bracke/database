--  Deterministic random data and operation generation for reliability tests.
with Interfaces;
with Database.Date_Time;
with Database.Schema;
with Database.Types;
with Database.Values;
with Database.UUIDs;

--  Deterministic randomized data and operation generation.
package Database.Randomized is
   --  Generator defines a public database type used by this package.
   type Generator is private;
   --  Operation_Kind defines a public database type used by this package.
   type Operation_Kind is
     (Insert_Row,
      Update_Row,
      Delete_Row,
      Read_Row,
      Commit_Tx,
      Rollback_Tx,
      Checkpoint,
      Vacuum,
      Backup,
      Restore,
      Create_Index,
      Rebuild_Index,
      Add_Column,
      Export_Data,
      Import_Data,
      Full_Text_Update,
      Rotate_Key);

   --  Predicate_Kind defines a public database type used by this package.
   type Predicate_Kind is
     (Predicate_Always_True,
      Predicate_Always_False,
      Predicate_Is_Null,
      Predicate_Equals_Integer,
      Predicate_Greater_Integer,
      Predicate_And,
      Predicate_Or,
      Predicate_Not);

   --  Index_Definition stores the public fields for this database abstraction.
   type Index_Definition is record
      Column_Id : Natural := 1;
      Unique    : Boolean := False;
      Partial   : Boolean := False;
   end record;

   --  Foreign_Key_Edge stores the public fields for this database abstraction.
   type Foreign_Key_Edge is record
      From_Table : Natural := 1;
      To_Table   : Natural := 1;
      From_Column : Natural := 1;
      To_Column   : Natural := 1;
   end record;

   --  Foreign_Key_Graph defines a public database type used by this package.
   type Foreign_Key_Graph is array (Positive range <>) of Foreign_Key_Edge;

   --  Perform reset for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Seed deterministic seed used for reproducible behavior.
   procedure Reset (G : out Generator; Seed : Natural);
   --  Return seed for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Seed (G : Generator) return Natural;
   --  Return next natural for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Upper_Bound upper bound argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Natural (G : in out Generator; Upper_Bound : Positive) return Natural
     with Post => Next_Natural'Result < Upper_Bound;
   --  Return next boolean for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Boolean (G : in out Generator) return Boolean;
   --  Return next operation for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Operation (G : in out Generator) return Operation_Kind;
   --  Return next integer value for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Next_Integer_Value (G : in out Generator) return Database.Values.Value;
   --  Return next unicode string for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Max_Length max length argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Unicode_String (G : in out Generator; Max_Length : Natural) return Wide_Wide_String;

   --  Return next value kind for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Next_Value_Kind (G : in out Generator) return Database.Types.Value_Kind;
   --  Return next value for kind for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @return Requested value or optional value according to the package contract.
   function Next_Value_For_Kind
     (G    : in out Generator;
      Kind : Database.Types.Value_Kind) return Database.Values.Value;
   --  Return next blob for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Max_Length max length argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Blob (G : in out Generator; Max_Length : Natural) return Database.Values.Byte_Vectors.Vector;
   --  Return next date for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Date (G : in out Generator) return Database.Date_Time.Date;
   --  Return next time for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Time (G : in out Generator) return Database.Date_Time.Time;
   --  Return next date time for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Date_Time (G : in out Generator) return Database.Date_Time.Date_Time;
   --  Return next uuid for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_UUID (G : in out Generator) return Database.UUIDs.UUID;
   --  Return next decimal for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Decimal (G : in out Generator) return Database.Types.Decimal;
   --  Return next enum literal for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Enum_Literal (G : in out Generator) return Wide_Wide_String;
   --  Return next bounded text for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Max_Length max length argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Bounded_Text
     (G          : in out Generator;
      Max_Length : Natural) return Database.Values.Value;

   --  Return next schema for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Name logical name of the object.
   --  @param Max_Columns max columns argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Schema
     (G           : in out Generator;
      Name        : Wide_Wide_String;
      Max_Columns : Positive) return Database.Schema.Table_Schema;
   --  Return next predicate kind for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Predicate_Kind (G : in out Generator) return Predicate_Kind;
   --  Return next index definition for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Column_Count column count argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Index_Definition
     (G            : in out Generator;
      Column_Count : Positive) return Index_Definition;
   --  Return next foreign key graph for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Table_Count table count argument supplied to the operation.
   --  @param Edges edges argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Foreign_Key_Graph
     (G             : in out Generator;
      Table_Count   : Positive;
      Edges         : Positive) return Foreign_Key_Graph;

private
   --  Generator stores the public fields for this database abstraction.
   type Generator is record
      Initial_Seed : Natural := 1;
      State : Interfaces.Unsigned_64 := 1;
   end record;
end Database.Randomized;
