with Database.Status;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Metrics;

package body Database.Fault_Hooks is
   use Ada.Strings.Wide_Wide_Unbounded;

   type Fault_State is record
      Enabled : Boolean := False;
      Countdown : Natural := 0;
      Counted : Boolean := False;
   end record;

   type Fault_State_Array is array (Fault_Kind) of Fault_State;
   type Crash_State_Array is array (Crash_Point) of Boolean;

   protected State is
      procedure Reset_All;
      procedure Set_Random_Seed (Seed : Natural);
      function Random_Seed return Natural;
      procedure Enable (Fault : Fault_Kind);
      procedure Disable (Fault : Fault_Kind);
      function Enabled (Fault : Fault_Kind) return Boolean;
      procedure Arm_After (Fault : Fault_Kind; Operations : Natural);
      procedure Consume_Fault (Fault : Fault_Kind; Hit : out Boolean);
      procedure Arm_Crash_Point (Point : Crash_Point);
      procedure Clear_Crash_Point (Point : Crash_Point);
      function Armed (Point : Crash_Point) return Boolean;
      procedure Consume_Crash (Point : Crash_Point; Hit : out Boolean);
   private
      Faults : Fault_State_Array;
      Crashes : Crash_State_Array := (others => False);
      Seed_Value : Natural := 1;
   end State;

   protected body State is
      procedure Reset_All is
      begin
         Faults := (others => (Enabled => False, Countdown => 0, Counted => False));
         Crashes := (others => False);
         Seed_Value := 1;
      end Reset_All;

      procedure Set_Random_Seed (Seed : Natural) is
      begin
         Seed_Value := Seed;
      end Set_Random_Seed;

      function Random_Seed return Natural is (Seed_Value);

      procedure Enable (Fault : Fault_Kind) is
      begin
         Faults (Fault).Enabled := True;
         Faults (Fault).Counted := False;
      end Enable;

      procedure Disable (Fault : Fault_Kind) is
      begin
         Faults (Fault) := (Enabled => False, Countdown => 0, Counted => False);
      end Disable;

      function Enabled (Fault : Fault_Kind) return Boolean is (Faults (Fault).Enabled);

      procedure Arm_After (Fault : Fault_Kind; Operations : Natural) is
      begin
         Faults (Fault).Enabled := True;
         Faults (Fault).Countdown := Operations;
         Faults (Fault).Counted := False;
      end Arm_After;

      procedure Consume_Fault (Fault : Fault_Kind; Hit : out Boolean) is
      begin
         if not Faults (Fault).Enabled then
            Hit := False;
            return;
         end if;

         if Faults (Fault).Countdown > 0 then
            Faults (Fault).Countdown := Faults (Fault).Countdown - 1;
            Hit := False;
            return;
         end if;

         Faults (Fault).Enabled := False;
         Faults (Fault).Counted := True;
         Hit := True;
      end Consume_Fault;

      procedure Arm_Crash_Point (Point : Crash_Point) is
      begin
         Crashes (Point) := True;
      end Arm_Crash_Point;

      procedure Clear_Crash_Point (Point : Crash_Point) is
      begin
         Crashes (Point) := False;
      end Clear_Crash_Point;

      function Armed (Point : Crash_Point) return Boolean is (Crashes (Point));

      procedure Consume_Crash (Point : Crash_Point; Hit : out Boolean) is
      begin
         if Crashes (Point) then
            Crashes (Point) := False;
            Hit := True;
         else
            Hit := False;
         end if;
      end Consume_Crash;
   end State;

   procedure Reset is
   begin
      State.Reset_All;
   end Reset;
   procedure Set_Seed (Seed : Natural) is
   begin
      State.Set_Random_Seed (Seed);
   end Set_Seed;
   function Current_Seed return Natural is (State.Random_Seed);
   procedure Enable_Fault (Fault : Fault_Kind) is
   begin
      State.Enable (Fault);
   end Enable_Fault;
   procedure Disable_Fault (Fault : Fault_Kind) is
   begin
      State.Disable (Fault);
   end Disable_Fault;
   function Fault_Enabled (Fault : Fault_Kind) return Boolean is (State.Enabled (Fault));
   procedure Arm_Fault_After (Fault : Fault_Kind; Operations : Natural) is
   begin
      State.Arm_After (Fault, Operations);
   end Arm_Fault_After;

   function Should_Fail (Fault : Fault_Kind) return Boolean is
      Hit : Boolean;
   begin
      State.Consume_Fault (Fault, Hit);
      if Hit then
         Database.Metrics.Increment_Fault_Injections;
      end if;
      return Hit;
   end Should_Fail;

   procedure Arm_Crash (Point : Crash_Point) is
   begin
      State.Arm_Crash_Point (Point);
   end Arm_Crash;
   procedure Clear_Crash (Point : Crash_Point) is
   begin
      State.Clear_Crash_Point (Point);
   end Clear_Crash;
   function Crash_Armed (Point : Crash_Point) return Boolean is (State.Armed (Point));

   function Should_Crash (Point : Crash_Point) return Boolean is
      Hit : Boolean;
   begin
      State.Consume_Crash (Point, Hit);
      if Hit then
         Database.Metrics.Increment_Fault_Injections;
      end if;
      return Hit;
   end Should_Crash;

   function Injected_Failure (Fault : Fault_Kind) return Database.Status.Result is
      pragma Unreferenced (Fault);
   begin
      return Database.Status.Failure
        (Database.Status.Fault_Injection_Error,
         "deterministic injected failure");
   end Injected_Failure;
end Database.Fault_Hooks;
