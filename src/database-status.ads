--  Structured status results returned by ordinary database operations.
--  Exceptions are not used for expected validation, storage, or transaction failures.
with Ada.Strings.Wide_Wide_Unbounded;

package Database.Status is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Status-code subtype re-exported from the root package.
   subtype Status_Code is Database.Status_Code;

   --  Result subtype re-exported from the root package.
   subtype Result is Database.Result;

   Ok : constant Status_Code := Database.Ok;
   Not_Open : constant Status_Code := Database.Not_Open;
   Already_Open : constant Status_Code := Database.Already_Open;
   Invalid_Argument : constant Status_Code := Database.Invalid_Argument;
   Not_Found : constant Status_Code := Database.Not_Found;
   Already_Exists : constant Status_Code := Database.Already_Exists;
   Schema_Mismatch : constant Status_Code := Database.Schema_Mismatch;
   Constraint_Error : constant Status_Code := Database.Constraint_Error;
   Transaction_Error : constant Status_Code := Database.Transaction_Error;
   Invalid_File : constant Status_Code := Database.Invalid_File;
   Corrupt_File : constant Status_Code := Database.Corrupt_File;
   Row_Too_Large : constant Status_Code := Database.Row_Too_Large;
   IOError : constant Status_Code := Database.IOError;
   Serialization_Error : constant Status_Code := Database.Serialization_Error;
   Corrupt_Index : constant Status_Code := Database.Corrupt_Index;
   Key_Not_Found : constant Status_Code := Database.Key_Not_Found;
   Duplicate_Key : constant Status_Code := Database.Duplicate_Key;
   Unsupported_Key_Type : constant Status_Code := Database.Unsupported_Key_Type;
   Invalid_Schema : constant Status_Code := Database.Invalid_Schema;
   Migration_Error : constant Status_Code := Database.Migration_Error;
   Unsupported_Migration : constant Status_Code := Database.Unsupported_Migration;
   Read_Only_Transaction : constant Status_Code := Database.Read_Only_Transaction;
   Transaction_Conflict : constant Status_Code := Database.Transaction_Conflict;
   Lock_Error : constant Status_Code := Database.Lock_Error;
   Serialization_Failure : constant Status_Code := Database.Serialization_Failure;
   Snapshot_Too_Old : constant Status_Code := Database.Snapshot_Too_Old;
   Version_Conflict : constant Status_Code := Database.Version_Conflict;
   WAL_Corruption : constant Status_Code := Database.WAL_Corruption;
   Replay_Failure : constant Status_Code := Database.Replay_Failure;
   Checkpoint_Failure : constant Status_Code := Database.Checkpoint_Failure;
   Invalid_LSN : constant Status_Code := Database.Invalid_LSN;
   Full_Text_Index_Error : constant Status_Code := Database.Full_Text_Index_Error;
   Invalid_Full_Text_Query : constant Status_Code := Database.Invalid_Full_Text_Query;
   Unsupported_Tokenizer : constant Status_Code := Database.Unsupported_Tokenizer;
   Unsupported_Normalization : constant Status_Code := Database.Unsupported_Normalization;
   Backup_Error : constant Status_Code := Database.Backup_Error;
   Restore_Error : constant Status_Code := Database.Restore_Error;
   Export_Error : constant Status_Code := Database.Export_Error;
   Import_Error : constant Status_Code := Database.Import_Error;
   Incompatible_Backup : constant Status_Code := Database.Incompatible_Backup;
   Corrupt_Backup : constant Status_Code := Database.Corrupt_Backup;
   Backup_Verification_Failed : constant Status_Code := Database.Backup_Verification_Failed;
   Encryption_Error : constant Status_Code := Database.Encryption_Error;
   Authentication_Failure : constant Status_Code := Database.Authentication_Failure;
   Invalid_Key : constant Status_Code := Database.Invalid_Key;
   Unsupported_Encryption_Format : constant Status_Code := Database.Unsupported_Encryption_Format;
   Corrupt_Encrypted_Page : constant Status_Code := Database.Corrupt_Encrypted_Page;
   Corrupt_Encrypted_WAL : constant Status_Code := Database.Corrupt_Encrypted_WAL;
   Key_Rotation_Failed : constant Status_Code := Database.Key_Rotation_Failed;
   Missing_Extension : constant Status_Code := Database.Missing_Extension;
   Extension_Version_Mismatch : constant Status_Code := Database.Extension_Version_Mismatch;
   Extension_Error : constant Status_Code := Database.Extension_Error;
   Invalid_Date : constant Status_Code := Database.Invalid_Date;
   Invalid_Time : constant Status_Code := Database.Invalid_Time;
   Invalid_UUID : constant Status_Code := Database.Invalid_UUID;
   Decimal_Overflow : constant Status_Code := Database.Decimal_Overflow;
   Invalid_Enum_Value : constant Status_Code := Database.Invalid_Enum_Value;
   Bounded_Text_Overflow : constant Status_Code := Database.Bounded_Text_Overflow;
   Unsupported_Type_Version : constant Status_Code := Database.Unsupported_Type_Version;
   Trace_Error : constant Status_Code := Database.Trace_Error;
   Metrics_Error : constant Status_Code := Database.Metrics_Error;
   Profiling_Error : constant Status_Code := Database.Profiling_Error;
   Event_Handler_Error : constant Status_Code := Database.Event_Handler_Error;
   Invariant_Failure : constant Status_Code := Database.Invariant_Failure;
   Corruption_Detected : constant Status_Code := Database.Corruption_Detected;
   Replay_Inconsistency : constant Status_Code := Database.Replay_Inconsistency;
   Fault_Injection_Error : constant Status_Code := Database.Fault_Injection_Error;
   Fuzzing_Failure : constant Status_Code := Database.Fuzzing_Failure;
   Verification_Failure : constant Status_Code := Database.Verification_Failure;

   --  Return a successful result.
   --  @return Successful status result.
   function Success return Result;

   --  Return a failed result with a diagnostic message.
   --  @param Code failure code to report.
   --  @param Message diagnostic message to attach to the result.
   --  @return Failed status result.
   function Failure (Code : Status_Code; Message : Wide_Wide_String) return Result;

   --  Return whether a result is successful.
   --  @param R result to inspect.
   --  @return True when R.Code is Ok.
   function Is_Ok (R : Result) return Boolean is (R.Code = Ok);
end Database.Status;
