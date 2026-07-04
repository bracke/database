with Database.Metrics;
with Database.Events;
with Database.Tracing;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Fault_Hooks;
with Database.Storage.File_IO;
package body Database.Encryption is
   function Enable_Encryption
     (DB     : in out Database.Handle;
      Config : Encryption_Config) return Database.Status.Result is
   begin
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Encryption_Verification) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Encryption_Verification);
      end if;
      if DB.Kind = Closed_Backend then
         return Database.Status.Failure (Database.Status.Not_Open, "database is not open");
      end if;

      case Config.Mode is
         when No_Encryption =>
            DB.Encryption_Enabled := False;
            DB.Encryption_Key_Id := 0;
            DB.WAL_Encryption_Enabled := False;
            return Database.Status.Success;

         when Encrypted =>
            if not Database.Keys.Is_Valid (Config.Key) then
               return Database.Status.Failure
                 (Database.Status.Invalid_Key, "encryption requires a valid key");
            end if;
            if DB.Kind = Persistent_Backend then
               declare
                  Rewrite : constant Database.Status.Result :=
                    Database.Storage.File_IO.Encrypt_Existing_Pages
                      (DB.File, Config.Key);
               begin
                  if not Database.Status.Is_Ok (Rewrite) then
                     return Rewrite;
                  end if;
               end;
            end if;
            DB.Encryption_Enabled := True;
            DB.Encryption_Format_Version := 1;
            DB.Encryption_Key_Id := Database.Keys.Identifier (Config.Key);
            DB.WAL_Encryption_Enabled := True;
            Database.Metrics.Increment_Encryption_Operations;
            Database.Tracing.Emit_Trace ((0, Database.Tracing.Encryption_Trace,
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("encryption enabled"), True));
            return Database.Status.Success;
      end case;
   end Enable_Encryption;

   function Disable_Encryption
     (DB : in out Database.Handle) return Database.Status.Result is
   begin
      if DB.Kind = Closed_Backend then
         return Database.Status.Failure (Database.Status.Not_Open, "database is not open");
      end if;
      DB.Encryption_Enabled := False;
      DB.Encryption_Key_Id := 0;
      DB.WAL_Encryption_Enabled := False;
      Database.Storage.File_IO.Disable_Encryption (DB.File);
      return Database.Status.Success;
   end Disable_Encryption;

   function Rotate_Key
     (DB      : in out Database.Handle;
      New_Key : Database.Keys.Encryption_Key) return Database.Status.Result is
   begin
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Key_Rotation) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error,
           "deterministic crash during key rotation");
      end if;
      if DB.Kind = Closed_Backend then
         return Database.Status.Failure (Database.Status.Not_Open, "database is not open");
      end if;
      if not Database.Keys.Is_Valid (New_Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "new encryption key is invalid");
      end if;
      if not DB.Encryption_Enabled then
         return Database.Status.Failure
           (Database.Status.Encryption_Error, "database encryption is not enabled");
      end if;

      --  The minimal re-key path records the new key id after the
      --  storage rewrite/checkpoint path has selected a replacement key.  The
      --  raw key is intentionally not persisted or exposed.
      DB.Encryption_Key_Id := Database.Keys.Identifier (New_Key);
      DB.WAL_Encryption_Enabled := True;
      Database.Storage.File_IO.Enable_Encryption (DB.File, New_Key);
      Database.Metrics.Increment_Encryption_Operations;
      Database.Events.Emit_Event ((Database.Events.Encryption_Key_Rotation,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("encryption key rotated")));
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Encryption_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("encryption key rotation"), True));
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Key_Rotation_Failed, "key rotation failed");
   end Rotate_Key;

   function Metadata (DB : Database.Handle) return Encryption_Metadata is
   begin
      return
        (Mode           => (if DB.Encryption_Enabled then Encrypted else No_Encryption),
         Format_Version => DB.Encryption_Format_Version,
         Key_Id         => DB.Encryption_Key_Id,
         WAL_Encrypted  => DB.WAL_Encryption_Enabled);
   end Metadata;
end Database.Encryption;
