with Database.Status;
with Database.Fault_Hooks;

package body Database.Fault_Injection is
   function To_Hook (Fault : Fault_Kind) return Database.Fault_Hooks.Fault_Kind is
     (Database.Fault_Hooks.Fault_Kind'Val (Fault_Kind'Pos (Fault)));

   function To_Hook (Point : Crash_Point) return Database.Fault_Hooks.Crash_Point is
     (Database.Fault_Hooks.Crash_Point'Val (Crash_Point'Pos (Point)));

   procedure Reset is
   begin
      Database.Fault_Hooks.Reset;
   end Reset;
   procedure Set_Seed (Seed : Natural) is
   begin
      Database.Fault_Hooks.Set_Seed (Seed);
   end Set_Seed;
   function Current_Seed return Natural is (Database.Fault_Hooks.Current_Seed);

   procedure Enable_Fault (Fault : Fault_Kind) is
   begin
      Database.Fault_Hooks.Enable_Fault (To_Hook (Fault));
   end Enable_Fault;

   procedure Disable_Fault (Fault : Fault_Kind) is
   begin
      Database.Fault_Hooks.Disable_Fault (To_Hook (Fault));
   end Disable_Fault;

   function Fault_Enabled (Fault : Fault_Kind) return Boolean is
     (Database.Fault_Hooks.Fault_Enabled (To_Hook (Fault)));

   procedure Arm_Fault_After (Fault : Fault_Kind; Operations : Natural) is
   begin
      Database.Fault_Hooks.Arm_Fault_After (To_Hook (Fault), Operations);
   end Arm_Fault_After;

   function Should_Fail (Fault : Fault_Kind) return Boolean is
     (Database.Fault_Hooks.Should_Fail (To_Hook (Fault)));

   procedure Arm_Crash (Point : Crash_Point) is
   begin
      Database.Fault_Hooks.Arm_Crash (To_Hook (Point));
   end Arm_Crash;

   procedure Clear_Crash (Point : Crash_Point) is
   begin
      Database.Fault_Hooks.Clear_Crash (To_Hook (Point));
   end Clear_Crash;

   function Crash_Armed (Point : Crash_Point) return Boolean is
     (Database.Fault_Hooks.Crash_Armed (To_Hook (Point)));

   function Should_Crash (Point : Crash_Point) return Boolean is
     (Database.Fault_Hooks.Should_Crash (To_Hook (Point)));

   function Injected_Failure (Fault : Fault_Kind) return Database.Status.Result is
     (Database.Fault_Hooks.Injected_Failure (To_Hook (Fault)));
end Database.Fault_Injection;
