with Ada.Containers.Indefinite_Vectors;
with Ada.Wide_Wide_Text_IO;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Tracing is
   use Ada.Strings.Wide_Wide_Unbounded;

   package Event_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Trace_Event);

   Enabled : Boolean := False;
   Sensitive_Enabled : Boolean := False;
   Category_Flags : array (Trace_Category) of Boolean := (others => True);
   Buffer : Event_Vectors.Vector;
   Max_Buffered : constant Natural := 256;
   Current_Sink : Sink_Access := null;
   Console_Enabled : Boolean := False;
   File_Enabled : Boolean := False;
   File : Ada.Wide_Wide_Text_IO.File_Type;
   Clock : Timestamp_Type := 0;

   procedure Enable is
   begin
      Enabled := True;
   end Enable;
   procedure Disable is
   begin
      Enabled := False;
   end Disable;
   function Is_Enabled return Boolean is (Enabled);
   procedure Enable_Category (Category : Trace_Category) is
   begin
      Category_Flags (Category) := True;
   end Enable_Category;

   procedure Disable_Category (Category : Trace_Category) is
   begin
      Category_Flags (Category) := False;
   end Disable_Category;

   function Category_Enabled (Category : Trace_Category) return Boolean is
     (Category_Flags (Category));
   procedure Enable_Sensitive_Traces is
   begin
      Sensitive_Enabled := True;
   end Enable_Sensitive_Traces;
   procedure Disable_Sensitive_Traces is
   begin
      Sensitive_Enabled := False;
   end Disable_Sensitive_Traces;
   function Sensitive_Traces_Enabled return Boolean is (Sensitive_Enabled);

   function Safe_Event (Event : Trace_Event) return Trace_Event is
      Result : Trace_Event := Event;
   begin
      if Event.Sensitive and then not Sensitive_Enabled then
         Result.Message := To_Unbounded_Wide_Wide_String ("[sensitive trace suppressed]");
      end if;
      return Result;
   end Safe_Event;

   function Emit_Trace (Event : Trace_Event) return Database.Status.Result is
      Stored : Trace_Event := Safe_Event (Event);
   begin
      if not Enabled or else not Category_Flags (Event.Category) then
         return Database.Status.Success;
      end if;
      Clock := Clock + 1;
      Stored.Timestamp := Clock;
      Buffer.Append (Stored);
      while Natural (Buffer.Length) > Max_Buffered loop
         Buffer.Delete_First;
      end loop;
      if Console_Enabled then
         begin
            Ada.Wide_Wide_Text_IO.Put_Line (To_Wide_Wide_String (Stored.Message));
         exception
            when others =>
               null;
         end;
      end if;
      if File_Enabled then
         begin
            Ada.Wide_Wide_Text_IO.Put_Line (File, To_Wide_Wide_String (Stored.Message));
            Ada.Wide_Wide_Text_IO.Flush (File);
         exception
            when others =>
               return Database.Status.Failure
                 (Database.Status.Trace_Error, "file trace sink failed");
         end;
      end if;
      if Current_Sink /= null then
         begin
            Current_Sink.all (Stored);
         exception
            when others =>
               return Database.Status.Failure
                 (Database.Status.Event_Handler_Error, "trace sink failed");
         end;
      end if;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Trace_Error, "trace emission failed");
   end Emit_Trace;

   procedure Emit_Trace (Event : Trace_Event) is
      R : constant Database.Status.Result := Emit_Trace (Event);
      pragma Unreferenced (R);
   begin
      null;
   end Emit_Trace;

   function Emit
     (Category  : Trace_Category;
      Message   : Wide_Wide_String;
      Sensitive : Boolean := False) return Database.Status.Result is
      E : Trace_Event;
   begin
      E.Category := Category;
      E.Message := To_Unbounded_Wide_Wide_String (Message);
      E.Sensitive := Sensitive;
      return Emit_Trace (E);
   end Emit;

   procedure Enable_Console_Sink is
   begin
      Console_Enabled := True;
   end Enable_Console_Sink;

   procedure Disable_Console_Sink is
   begin
      Console_Enabled := False;
   end Disable_Console_Sink;

   function Enable_File_Sink (Path : String) return Database.Status.Result is
   begin
      if File_Enabled then
         Ada.Wide_Wide_Text_IO.Close (File);
         File_Enabled := False;
      end if;
      Ada.Wide_Wide_Text_IO.Create
        (File => File,
         Mode => Ada.Wide_Wide_Text_IO.Out_File,
         Name => Path);
      File_Enabled := True;
      return Database.Status.Success;
   exception
      when others =>
         File_Enabled := False;
         return Database.Status.Failure
           (Database.Status.Trace_Error, "could not open trace file sink");
   end Enable_File_Sink;

   procedure Disable_File_Sink is
   begin
      if File_Enabled then
         Ada.Wide_Wide_Text_IO.Close (File);
      end if;
      File_Enabled := False;
   exception
      when others =>
         File_Enabled := False;
   end Disable_File_Sink;

   procedure Set_Custom_Sink (Sink : Sink_Access) is
   begin
      Current_Sink := Sink;
   end Set_Custom_Sink;
   procedure Clear_Custom_Sink is
   begin
      Current_Sink := null;
   end Clear_Custom_Sink;
   procedure Clear_Buffer is
   begin
      Buffer.Clear;
   end Clear_Buffer;
   function Buffered_Count return Natural is (Natural (Buffer.Length));
   function Buffered_Event (Index : Natural) return Trace_Event is
   begin
      return Buffer.Element (Index);
   end Buffered_Event;

   procedure Reset is
   begin
      Enabled := False;
      Sensitive_Enabled := False;
      Category_Flags := (others => True);
      Buffer.Clear;
      Current_Sink := null;
      Console_Enabled := False;
      Disable_File_Sink;
      Clock := 0;
   end Reset;
end Database.Tracing;
