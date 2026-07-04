with Database.WAL;

package body Database.Replay is
   function Replay_WAL
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result is
   begin
      return Database.WAL.Replay_Committed (Database_Path, F);
   end Replay_WAL;

   function Validate_WAL (Database_Path : Wide_Wide_String) return Database.Status.Result is
   begin
      return Database.WAL.Validate (Database_Path);
   end Validate_WAL;
end Database.Replay;
