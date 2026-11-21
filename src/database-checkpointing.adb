with Ada.Characters.Conversions;
with Ada.Exceptions;
with Database.Checkpoint_Merge;

package body Database.Checkpointing is
   function Checkpoint
     (DB   : in out Database.Handle;
      Mode : Checkpoint_Mode := Full) return Database.Status.Result is
      pragma Unreferenced (Mode);
      R       : Database.Status.Result;
      Granted : Boolean;
   begin
      if not Database.Is_Open (DB) then
         return Database.Status.Failure (Database.Status.Not_Open, "database not open");
      end if;
      if Database.Backend (DB) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;
      --  The checkpoint writes pages, may cut the file back and rescans the free pages, so no transaction may write
      --  meanwhile: it holds the write lock throughout instead of only checking that no writer is active.
      DB.Lock.Try_Begin_Exclusive (Granted);
      if not Granted then
         return Database.Status.Failure (Database.Status.Checkpoint_Failure,
           "checkpoint cannot run while writer is active");
      end if;
      begin
         R := Database.Checkpoint_Merge.Merge_WAL (DB);
      exception
         when E : others =>
            R := Database.Status.Failure
              (Database.Status.Checkpoint_Failure,
               "checkpoint failed: "
               & Ada.Characters.Conversions.To_Wide_Wide_String (Ada.Exceptions.Exception_Message (E)));
      end;
      DB.Lock.End_Write;
      return R;
   end Checkpoint;
end Database.Checkpointing;
