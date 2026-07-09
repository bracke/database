with Ada.Command_Line;
with Ada.Characters.Conversions;
with Ada.Text_IO;

with Database;

procedure Lock_Holder is
   DB : Database.Handle;
   Ready : Ada.Text_IO.File_Type;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Database.Open
     (DB,
      Ada.Characters.Conversions.To_Wide_Wide_String
        (Ada.Command_Line.Argument (1)));
   if not Database.Last_Operation_Succeeded (DB) then
      Ada.Command_Line.Set_Exit_Status (3);
      return;
   end if;

   Ada.Text_IO.Create (Ready, Ada.Text_IO.Out_File, Ada.Command_Line.Argument (2));
   Ada.Text_IO.Put_Line (Ready, "ready");
   Ada.Text_IO.Close (Ready);

   delay 2.0;
   Database.Close (DB);
   if Database.Last_Operation_Succeeded (DB) then
      Ada.Command_Line.Set_Exit_Status (0);
   else
      Ada.Command_Line.Set_Exit_Status (4);
   end if;
end Lock_Holder;
