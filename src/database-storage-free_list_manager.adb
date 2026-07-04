with Interfaces;
package body Database.Storage.Free_List_Manager
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_32;

   function Page_Is_Usable
     (Page         : Page_Id_Type;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type) return Boolean
   is
   begin
      return Page /= No_Page
        and then Page >= First_Usable
        and then Page <= Page_Count;
   end Page_Is_Usable;

   function Is_Sorted_Unique (List : Free_List) return Boolean is
   begin
      if List.Count > Max_Free_Pages then
         return False;
      end if;

      if List.Count = 0 then
         return True;
      end if;

      for Index in 1 .. List.Count loop
         pragma Loop_Invariant (Index in 1 .. List.Count);

         if List.Pages (Index) = No_Page then
            return False;
         end if;

         if Index > 1 and then List.Pages (Index - 1) >= List.Pages (Index) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Sorted_Unique;

   function Contains
     (List : Free_List;
      Page : Page_Id_Type) return Boolean
   is
   begin
      if Page = No_Page then
         return False;
      end if;

      for Index in 1 .. List.Count loop
         pragma Loop_Invariant (Index in 1 .. List.Count);

         if List.Pages (Index) = Page then
            return True;
         elsif List.Pages (Index) > Page then
            return False;
         end if;
      end loop;

      return False;
   end Contains;

   function Validate
     (List        : Free_List;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type) return Validation_Status
   is
   begin
      if List.Count > Max_Free_Pages then
         return Invalid_Count;
      end if;

      for Index in 1 .. List.Count loop
         pragma Loop_Invariant (Index in 1 .. List.Count);

         if List.Pages (Index) = No_Page then
            return Contains_No_Page;
         end if;

         if List.Pages (Index) < First_Usable then
            return Contains_Reserved_Page;
         end if;

         if List.Pages (Index) > Page_Count then
            return Contains_Out_Of_Range_Page;
         end if;

         if Index > 1 then
            if List.Pages (Index - 1) = List.Pages (Index) then
               return Contains_Duplicate;
            elsif List.Pages (Index - 1) > List.Pages (Index) then
               return Not_Sorted;
            end if;
         end if;
      end loop;

      return Valid;
   end Validate;

   procedure Clear (List : out Free_List) is
   begin
      List.Count := 0;
      List.Pages := (others => No_Page);
   end Clear;

   procedure Add_Free_Page
     (List         : in out Free_List;
      Page         : Page_Id_Type;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Status       : out Operation_Status)
   is
      Insert_At : Natural := 1;
   begin
      if Validate (List, First_Usable, Page_Count) /= Valid then
         Status := Corrupt_Free_List;
         return;
      end if;

      if not Page_Is_Usable (Page, First_Usable, Page_Count) then
         Status := Invalid_Page_Id;
         return;
      end if;

      if List.Count = Max_Free_Pages then
         Status := Free_List_Full;
         return;
      end if;

      if Contains (List, Page) then
         Status := Page_Already_Free;
         return;
      end if;

      while Insert_At <= List.Count and then List.Pages (Insert_At) < Page loop
         pragma Loop_Invariant (Insert_At in 1 .. List.Count + 1);
         Insert_At := Insert_At + 1;
      end loop;

      if List.Count > 0 then
         for Index in reverse Insert_At .. List.Count loop
            pragma Loop_Invariant (Index in Insert_At .. List.Count);
            List.Pages (Index + 1) := List.Pages (Index);
         end loop;
      end if;

      List.Pages (Insert_At) := Page;
      List.Count := List.Count + 1;
      Status := Operation_OK;
   end Add_Free_Page;

   procedure Allocate_Free_Page
     (List         : in out Free_List;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Page         : out Page_Id_Type;
      Status       : out Operation_Status)
   is
   begin
      Page := No_Page;

      if Validate (List, First_Usable, Page_Count) /= Valid then
         Status := Corrupt_Free_List;
         return;
      end if;

      if List.Count = 0 then
         Status := Page_Not_Free;
         return;
      end if;

      Page := List.Pages (List.Count);
      List.Pages (List.Count) := No_Page;
      List.Count := List.Count - 1;
      Status := Operation_OK;
   end Allocate_Free_Page;

   procedure Remove_Free_Page
     (List         : in out Free_List;
      Page         : Page_Id_Type;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Status       : out Operation_Status)
   is
      Found_Index : Natural := 0;
   begin
      if Validate (List, First_Usable, Page_Count) /= Valid then
         Status := Corrupt_Free_List;
         return;
      end if;

      if not Page_Is_Usable (Page, First_Usable, Page_Count) then
         Status := Invalid_Page_Id;
         return;
      end if;

      for Index in 1 .. List.Count loop
         pragma Loop_Invariant (Index in 1 .. List.Count);

         if List.Pages (Index) = Page then
            Found_Index := Index;
            exit;
         elsif List.Pages (Index) > Page then
            exit;
         end if;
      end loop;

      if Found_Index = 0 then
         Status := Page_Not_Free;
         return;
      end if;

      if Found_Index < List.Count then
         for Index in Found_Index .. List.Count - 1 loop
            pragma Loop_Invariant (Index in Found_Index .. List.Count - 1);
            List.Pages (Index) := List.Pages (Index + 1);
         end loop;
      end if;

      List.Pages (List.Count) := No_Page;
      List.Count := List.Count - 1;
      Status := Operation_OK;
   end Remove_Free_Page;

end Database.Storage.Free_List_Manager;
