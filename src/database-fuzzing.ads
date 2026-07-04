--  Fuzzing harnesses for malformed durable formats.
with Ada.Streams;
with Database.Status;

--  Malformed input fuzzing support.
package Database.Fuzzing is
   --  Fuzz_Target defines a public database type used by this package.
   type Fuzz_Target is
     (Page_Parser,
      WAL_Replay_Parser,
      Record_Decoder,
      Import_Parser,
      Backup_Manifest_Parser,
      Encryption_Metadata_Parser,
      Full_Text_Structure_Parser);

   --  Fuzz_Result stores the public fields for this database abstraction.
   type Fuzz_Result is record
      Status : Database.Status.Result := Database.Status.Success;
      Inputs_Tested : Natural := 0;
      Inputs_Rejected : Natural := 0;
      Inputs_Accepted : Natural := 0;
      Max_Input_Length_Observed : Natural := 0;
      Minimal_Rejected_Length : Natural := Natural'Last;
   end record;

   --  Fuzz_Options stores the public fields for this database abstraction.
   type Fuzz_Options is record
      Max_Input_Length : Natural := 8_192;
      Include_Boundary_Cases : Boolean := True;
      Include_Mutations : Boolean := True;
      Stop_On_First_Unexpected_Acceptance : Boolean := False;
   end record;

   --  Default_Fuzz_Options is a public constant used by this package.
   Default_Fuzz_Options : constant Fuzz_Options  :=
     (Max_Input_Length => 8_192,
      Include_Boundary_Cases => True,
      Include_Mutations => True,
      Stop_On_First_Unexpected_Acceptance => False);

   --  Return fuzz input for the supplied database state or arguments.
   --  @param Target target argument supplied to the operation.
   --  @param Data byte data processed by the operation.
   --  @return Result produced by the function.
   function Fuzz_Input
     (Target : Fuzz_Target;
      Data   : Ada.Streams.Stream_Element_Array) return Fuzz_Result;

   --  Return fuzz deterministic for the supplied database state or arguments.
   --  @param Target target argument supplied to the operation.
   --  @param Seed deterministic seed used for reproducible behavior.
   --  @param Count count argument supplied to the operation.
   --  @return Result produced by the function.
   function Fuzz_Deterministic
     (Target : Fuzz_Target;
      Seed   : Natural;
      Count  : Natural) return Fuzz_Result;

   --  Return fuzz deterministic for the supplied database state or arguments.
   --  @param Target target argument supplied to the operation.
   --  @param Seed deterministic seed used for reproducible behavior.
   --  @param Count count argument supplied to the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Fuzz_Deterministic
     (Target  : Fuzz_Target;
      Seed    : Natural;
      Count   : Natural;
      Options : Fuzz_Options) return Fuzz_Result;

   --  Return fuzz corpus for the supplied database state or arguments.
   --  @param Target target argument supplied to the operation.
   --  @param Seed deterministic seed used for reproducible behavior.
   --  @param Count count argument supplied to the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Fuzz_Corpus
     (Target  : Fuzz_Target;
      Seed    : Natural;
      Count   : Natural;
      Options : Fuzz_Options := Default_Fuzz_Options) return Fuzz_Result;

   --  Return fuzz all targets for the supplied database state or arguments.
   --  @param Seed deterministic seed used for reproducible behavior.
   --  @param Count_Per_Target count per target argument supplied to the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Requested value or optional value according to the package contract.
   function Fuzz_All_Targets
     (Seed    : Natural;
      Count_Per_Target : Natural;
      Options : Fuzz_Options := Default_Fuzz_Options) return Fuzz_Result;
end Database.Fuzzing;
