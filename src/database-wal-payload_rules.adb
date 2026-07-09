package body Database.WAL.Payload_Rules
  with SPARK_Mode => On
is
   function Expected_Payload_Length (Kind : Record_Kind) return Natural is
   begin
      case Kind is
         when Page_Frame =>
            return Page_Frame_Payload_Length;
         when Commit_Record =>
            return Commit_Payload_Length;
         when Checkpoint_Record =>
            return Checkpoint_Payload_Length;
         when Full_Text_Redo_Record | Full_Text_Undo_Record =>
            return Full_Text_Payload_Length;
      end case;
   end Expected_Payload_Length;

   function Payload_Length_Is_Valid
     (Kind   : Record_Kind;
      Length : Natural) return Boolean
   is
   begin
      return Length = Expected_Payload_Length (Kind);
   end Payload_Length_Is_Valid;
end Database.WAL.Payload_Rules;
