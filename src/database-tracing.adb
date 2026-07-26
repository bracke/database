with Ada.Containers.Indefinite_Vectors;
with Ada.Wide_Wide_Text_IO;

package body Database.Tracing is

   package Event_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Trace_Event);

   Max_Buffered : constant Natural := 256;

   --  Configuration flags. These are meant to be set at setup time (before
   --  concurrent operation); the scalar toggles are atomic so a stray runtime
   --  Enable/Disable is at least well-defined, and Category_Flags uses atomic
   --  components for the same reason. The File / Console text sinks are not
   --  internally serialized across tasks -- for concurrent multi-database load,
   --  install a Custom_Sink that serializes rather than the built-in file sink.
   Enabled : Boolean := False;
   pragma Atomic (Enabled);
   Sensitive_Enabled : Boolean := False;
   pragma Atomic (Sensitive_Enabled);
   Category_Flags : array (Trace_Category) of Boolean := [others => True];
   pragma Atomic_Components (Category_Flags);
   Current_Sink : Sink_Access := null;
   pragma Atomic (Current_Sink);
   Console_Enabled : Boolean := False;
   pragma Atomic (Console_Enabled);
   File_Enabled : Boolean := False;
   pragma Atomic (File_Enabled);
   File : Ada.Wide_Wide_Text_IO.File_Type;

   --  Operation-path mutable state. Emit_Trace is called from many subsystems
   --  on the hot path, so the ring buffer and the logical clock are serialized
   --  here; concurrent multi-database tasks would otherwise corrupt the shared
   --  Buffer. No I/O and no user sink runs under this lock -- Emit_Trace does
   --  those outside it.
   protected Log is
      procedure Record_Event (Event : in out Trace_Event);
      procedure Clear;
      procedure Reset;
      function Count return Natural;
      function Element (Index : Natural) return Trace_Event;
   private
      Buffer : Event_Vectors.Vector;
      Clock  : Timestamp_Type := 0;
   end Log;

   protected body Log is
      procedure Record_Event (Event : in out Trace_Event) is
      begin
         Clock := Clock + 1;
         Event.Timestamp := Clock;
         Buffer.Append (Event);
         while Natural (Buffer.Length) > Max_Buffered loop
            Buffer.Delete_First;
         end loop;
      end Record_Event;
      procedure Clear is
      begin
         Buffer.Clear;
      end Clear;
      procedure Reset is
      begin
         Buffer.Clear;
         Clock := 0;
      end Reset;
      function Count return Natural is (Natural (Buffer.Length));
      function Element (Index : Natural) return Trace_Event is
        (Buffer.Element (Index));
   end Log;

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
      Log.Record_Event (Stored);  --  serialized: stamps, buffers, and trims
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
      Log.Clear;
   end Clear_Buffer;
   function Buffered_Count return Natural is (Log.Count);
   function Buffered_Event (Index : Natural) return Trace_Event is
   begin
      return Log.Element (Index);
   end Buffered_Event;

   procedure Reset is
   begin
      Enabled := False;
      Sensitive_Enabled := False;
      Category_Flags := [others => True];
      Log.Reset;
      Current_Sink := null;
      Console_Enabled := False;
      Disable_File_Sink;
   end Reset;
end Database.Tracing;
