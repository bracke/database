with AUnit.Test_Cases;

package Record_Serializer_Tests is
   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Case_Type);
   overriding function Name (T : Case_Type) return AUnit.Message_String;
end Record_Serializer_Tests;
