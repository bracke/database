with AUnit.Test_Cases;

package Registry_Ownership_Tests is
   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;
   overriding function Name (T : Case_Type) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Case_Type);
end Registry_Ownership_Tests;
