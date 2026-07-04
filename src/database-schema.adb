with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;

package body Database.Schema is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;

   procedure Add_Column
     (S           : in out Table_Schema;
      Name        : Wide_Wide_String;
      Kind        : Database.Types.Value_Kind;
      Nullable    : Boolean := True;
      Primary_Key : Boolean := False) is
      C : Column;
   begin
      C.Id := S.Next_Column_Id;
      C.Name := To_Unbounded_Wide_Wide_String (Name);
      C.Kind := Kind;
      C.Type_Info := Database.Types.Describe (Kind);
      C.Nullable := Nullable;
      C.Primary_Key := Primary_Key;
      S.Columns.Append (C);
      if Primary_Key then
         S.Primary_Key_Columns.Append (C.Id);
      end if;
      S.Next_Column_Id := S.Next_Column_Id + 1;
   end Add_Column;

   function Column_Count (S : Table_Schema) return Natural is
   begin
      return Natural (S.Columns.Length);
   end Column_Count;

   function Primary_Key_Index (S : Table_Schema) return Natural is
   begin
      if S.Columns.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (S.Columns.Length) - 1 loop
         if S.Columns.Element (I).Primary_Key then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Primary_Key_Index;

   function Primary_Key_Column_Count (S : Table_Schema) return Natural is
   begin
      if S.Primary_Key_Columns.Length > 0 then
         return Natural (S.Primary_Key_Columns.Length);
      end if;
      if Primary_Key_Index (S) = Natural'Last then
         return 0;
      end if;
      return 1;
   end Primary_Key_Column_Count;

   function Is_Primary_Key_Column (S : Table_Schema; Column_Id : Natural) return Boolean is
   begin
      for C of S.Primary_Key_Columns loop
         if C = Column_Id then
            return True;
         end if;
      end loop;
      declare
         P : constant Natural := Find_Column_Id_Position (S, Column_Id);
      begin
         return P /= Natural'Last and then S.Columns.Element (P).Primary_Key;
      end;
   end Is_Primary_Key_Column;

   function Contains_Column_Name (S : Table_Schema; Name : Wide_Wide_String) return Boolean is
   begin
      return Find_Column_Position (S, Name) /= Natural'Last;
   end Contains_Column_Name;

   function Find_Column_Position (S : Table_Schema; Name : Wide_Wide_String) return Natural is
   begin
      if S.Columns.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (S.Columns.Length) - 1 loop
         if To_Wide_Wide_String (S.Columns.Element (I).Name) = Name then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Column_Position;

   function Find_Column_Id_Position (S : Table_Schema; Column_Id : Natural) return Natural is
   begin
      if S.Columns.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (S.Columns.Length) - 1 loop
         if S.Columns.Element (I).Id = Column_Id then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Column_Id_Position;

   function Next_Id (S : Table_Schema) return Natural is
      Max_Id : Natural := 0;
   begin
      if S.Columns.Length = 0 then
         return 0;
      end if;
      for C of S.Columns loop
         if C.Id >= Max_Id then
            Max_Id := C.Id + 1;
         end if;
      end loop;
      return Natural'Max (S.Next_Column_Id, Max_Id);
   end Next_Id;
end Database.Schema;
