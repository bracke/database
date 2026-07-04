with Database;

procedure Main is
   DB : Database.Handle;
begin
   Database.Open_In_Memory (DB);
   pragma Assert (Database.Is_Open (DB), "database did not open");
   Database.Close (DB);
end Main;
