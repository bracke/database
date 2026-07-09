package Database.WAL
  with SPARK_Mode => On
is
   type Record_Kind is
     (Page_Frame,
      Commit_Record,
      Checkpoint_Record,
      Full_Text_Redo_Record,
      Full_Text_Undo_Record);
end Database.WAL;
