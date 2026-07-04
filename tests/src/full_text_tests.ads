with AUnit.Test_Cases;
package Full_Text_Tests is
   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;
   overriding function Name (T : Case_Type) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Case_Type);
end Full_Text_Tests;
