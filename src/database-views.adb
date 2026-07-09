with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
package body Database.Views is
   use type Ada.Containers.Count_Type;
   function Create (Name : Wide_Wide_String; Query : Database.Queries.Query) return View_Definition is
   begin
      return (Id => 0, Name => To_Unbounded_Wide_Wide_String (Name), Query => Query);
   end Create;
   function Validate (View : View_Definition) return Database.Status.Result is
   begin
      if Length (View.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "view name must not be empty");
      end if;
      return Database.Status.Success;
   end Validate;
   function Expand (View : View_Definition; Query : out Database.Queries.Query) return Database.Status.Result is
   begin
      Query := View.Query;
      return Validate (View);
   end Expand;

   function Is_Updatable (View : View_Definition) return Boolean is
   begin
      return Database.Status.Is_Ok (Validate (View));
   end Is_Updatable;

   function Insert_Row
     (View : in out View_Definition;
      Row  : Database.Rows.Row) return Database.Status.Result is
      R    : Database.Status.Result := Validate (View);
      Rows : Database.Queries.Row_Vectors.Vector;
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Rows := Database.Queries.Rows (View.Query);
      Rows.Append (Row);
      View.Query := Database.Queries.From_Rows (Rows);
      return Database.Status.Success;
   end Insert_Row;

   function Update_Row
     (View       : in out View_Definition;
      Key_Column : Natural;
      Row        : Database.Rows.Row) return Database.Status.Result is
      R        : Database.Status.Result := Validate (View);
      Rows     : Database.Queries.Row_Vectors.Vector;
      Existing : Database.Rows.Row;
      Key      : Database.Values.Value;
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      elsif Key_Column >= Database.Rows.Column_Count (Row) then
         return Database.Status.Failure
           (Database.Status.Invalid_Argument, "view update key column is outside row");
      end if;

      Key := Database.Rows.Get (Row, Key_Column);
      Rows := Database.Queries.Rows (View.Query);
      if Rows.Length > 0 then
         for I in 0 .. Natural (Rows.Length) - 1 loop
            Existing := Rows.Element (I);
            if Key_Column < Database.Rows.Column_Count (Existing)
              and then Database.Values.Equal
                (Database.Rows.Get (Existing, Key_Column), Key)
            then
               Rows.Replace_Element (I, Row);
               View.Query := Database.Queries.From_Rows (Rows);
               return Database.Status.Success;
            end if;
         end loop;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "view row not found");
   end Update_Row;

   function Delete_Row
     (View       : in out View_Definition;
      Key_Column : Natural;
      Key        : Database.Values.Value) return Database.Status.Result is
      R        : Database.Status.Result := Validate (View);
      Rows     : Database.Queries.Row_Vectors.Vector;
      Existing : Database.Rows.Row;
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Rows := Database.Queries.Rows (View.Query);
      if Rows.Length > 0 then
         for I in 0 .. Natural (Rows.Length) - 1 loop
            Existing := Rows.Element (I);
            if Key_Column < Database.Rows.Column_Count (Existing)
              and then Database.Values.Equal
                (Database.Rows.Get (Existing, Key_Column), Key)
            then
               Rows.Delete (I);
               View.Query := Database.Queries.From_Rows (Rows);
               return Database.Status.Success;
            end if;
         end loop;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "view row not found");
   end Delete_Row;
end Database.Views;
