package Database.WAL.Payload_Rules
  with SPARK_Mode => On
is
   Page_Frame_Payload_Length : constant Natural := 4096;
   Full_Text_Payload_Length  : constant Natural := 4096;
   Commit_Payload_Length     : constant Natural := 4;
   Checkpoint_Payload_Length : constant Natural := 0;

   function Expected_Payload_Length (Kind : Record_Kind) return Natural
     with
       Global => null,
       Post =>
         (case Kind is
            when Page_Frame => Expected_Payload_Length'Result = Page_Frame_Payload_Length,
            when Commit_Record => Expected_Payload_Length'Result = Commit_Payload_Length,
            when Checkpoint_Record => Expected_Payload_Length'Result = Checkpoint_Payload_Length,
            when Full_Text_Redo_Record | Full_Text_Undo_Record =>
              Expected_Payload_Length'Result = Full_Text_Payload_Length);

   function Payload_Length_Is_Valid
     (Kind   : Record_Kind;
      Length : Natural) return Boolean
     with
       Global => null,
       Post => Payload_Length_Is_Valid'Result =
         (Length = Expected_Payload_Length (Kind));
end Database.WAL.Payload_Rules;
