with Ada.Characters.Conversions;
with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Wide_Wide_Text_IO;

with Database;
with Database.Inspect;
with Database.Keys;
with Database.Status;

procedure Database_Inspect is
   use Ada.Command_Line;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada.Wide_Wide_Text_IO;

   procedure Put_Output (Line : Wide_Wide_String) is
   begin
      Put_Line (Line);
   end Put_Output;

   function Arg (Index : Positive) return Wide_Wide_String is
   begin
      return Ada.Characters.Conversions.To_Wide_Wide_String (Argument (Index));
   end Arg;

   function Usage return Wide_Wide_String is
   begin
      return
        "usage: database_inspect [--encrypted [--passphrase-env NAME]] "
        & "<database> schemas | tables | indexes | dump <table|--all> [limit]";
   end Usage;

   function Version_Text return Wide_Wide_String is
   begin
      return "database_inspect 0.14.0";
   end Version_Text;

   function Parse_Limit (Index : Positive) return Natural is
      Text   : constant String := Argument (Index);
      Result : Natural := 0;
   begin
      if Text'Length = 0 then
         raise Constraint_Error;
      end if;

      for Ch of Text loop
         if Ch not in '0' .. '9' then
            raise Constraint_Error;
         end if;
         Result := Result * 10 + Character'Pos (Ch) - Character'Pos ('0');
      end loop;
      return Result;
   end Parse_Limit;

   procedure Fail (Message : Wide_Wide_String) is
   begin
      Put_Line (Standard_Error, Message);
      Set_Exit_Status (Failure);
   end Fail;

   DB             : Database.Handle;
   R              : Database.Status.Result;
   Command        : Unbounded_Wide_Wide_String;
   Encrypted      : Boolean := False;
   Passphrase_Env : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.To_Unbounded_String
       ("DATABASE_INSPECT_PASSPHRASE");
   First_Pos      : Positive := 1;
   Key            : Database.Keys.Encryption_Key := Database.Keys.Empty_Key;
begin
   if Argument_Count = 1
     and then (Argument (1) = "--help" or else Argument (1) = "help")
   then
      Put_Line (Usage);
      return;
   end if;

   if Argument_Count = 1
     and then (Argument (1) = "--version" or else Argument (1) = "version")
   then
      Put_Line (Version_Text);
      return;
   end if;

   while First_Pos <= Argument_Count loop
      if Argument (First_Pos) = "--encrypted" then
         Encrypted := True;
         First_Pos := First_Pos + 1;
      elsif Argument (First_Pos) = "--passphrase-env" then
         if First_Pos + 1 > Argument_Count then
            Fail (Usage);
            return;
         end if;
         Passphrase_Env :=
           Ada.Strings.Unbounded.To_Unbounded_String
             (Argument (First_Pos + 1));
         First_Pos := First_Pos + 2;
      else
         exit;
      end if;
   end loop;

   if Argument_Count - First_Pos + 1 < 2 then
      Fail (Usage);
      return;
   end if;

   if Encrypted then
      if not Ada.Environment_Variables.Exists
        (Ada.Strings.Unbounded.To_String (Passphrase_Env))
      then
         Fail
           ("encrypted open requires environment variable "
            & Ada.Characters.Conversions.To_Wide_Wide_String
                (Ada.Strings.Unbounded.To_String (Passphrase_Env)));
         return;
      end if;

      Key := Database.Keys.Derive_Key
        (Ada.Characters.Conversions.To_Wide_Wide_String
           (Ada.Environment_Variables.Value
              (Ada.Strings.Unbounded.To_String (Passphrase_Env))),
         Database.Keys.Default_Salt);
      Database.Open_Encrypted (DB, Arg (First_Pos), Key);
   else
      Database.Open (DB, Arg (First_Pos));
   end if;

   if not Database.Last_Operation_Succeeded (DB) then
      R := Database.Last_Result (DB);
      if Encrypted then
         Database.Keys.Clear (Key);
      end if;
      Fail ("open failed: " & To_Wide_Wide_String (R.Message));
      return;
   end if;

   Command := To_Unbounded_Wide_Wide_String (Arg (First_Pos + 1));

   if To_Wide_Wide_String (Command) = "schemas"
     or else To_Wide_Wide_String (Command) = "tables"
   then
      if Argument_Count - First_Pos + 1 /= 2 then
         Fail (Usage);
         Database.Close (DB);
         if Encrypted then
            Database.Keys.Clear (Key);
         end if;
         return;
      end if;
      R := Database.Inspect.List_Schemas (DB, Put_Output'Unrestricted_Access);
   elsif To_Wide_Wide_String (Command) = "indexes" then
      if Argument_Count - First_Pos + 1 /= 2 then
         Fail (Usage);
         Database.Close (DB);
         if Encrypted then
            Database.Keys.Clear (Key);
         end if;
         return;
      end if;
      R := Database.Inspect.List_Indexes (DB, Put_Output'Unrestricted_Access);
   elsif To_Wide_Wide_String (Command) = "dump" then
      declare
         Limit : Natural := Natural'Last;
      begin
         if Argument_Count - First_Pos + 1 < 3 then
            Fail (Usage);
            Database.Close (DB);
            if Encrypted then
               Database.Keys.Clear (Key);
            end if;
            return;
         end if;
         if Argument_Count - First_Pos + 1 >= 4 then
            begin
               Limit := Parse_Limit (First_Pos + 3);
            exception
               when Constraint_Error =>
                  Fail ("invalid row limit: " & Arg (First_Pos + 3));
                  Database.Close (DB);
                  if Encrypted then
                     Database.Keys.Clear (Key);
                  end if;
                  return;
            end;
         end if;

         if Argument_Count - First_Pos + 1 > 4 then
            Fail (Usage);
            Database.Close (DB);
            if Encrypted then
               Database.Keys.Clear (Key);
            end if;
            return;
         end if;

         if Arg (First_Pos + 2) = "--all" then
            R := Database.Inspect.Dump_All
              (DB, Put_Output'Unrestricted_Access, Limit);
         else
            R := Database.Inspect.Dump_Table
              (DB, Arg (First_Pos + 2), Put_Output'Unrestricted_Access, Limit);
         end if;
      end;
   else
      Fail (Usage);
      Database.Close (DB);
      if Encrypted then
         Database.Keys.Clear (Key);
      end if;
      return;
   end if;

   if not Database.Status.Is_Ok (R) then
      Fail ("inspect failed: " & To_Wide_Wide_String (R.Message));
   end if;

   Database.Close (DB);
   if Encrypted then
      Database.Keys.Clear (Key);
   end if;
exception
   when others =>
      if Encrypted then
         Database.Keys.Clear (Key);
      end if;
      Fail ("inspect failed with an unexpected exception");
end Database_Inspect;
