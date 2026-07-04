with Interfaces;

package Database.Storage.Free_List_Manager
  with SPARK_Mode => On
is
   --  Page_Id_Type defines a public database type used by this package.
   subtype Page_Id_Type is Interfaces.Unsigned_32;

   --  No_Page is a public constant used by this package.
   No_Page : constant Page_Id_Type := 0;

   --  Max_Free_Pages is a public constant used by this package.
   Max_Free_Pages : constant Natural := 4_096;

   --  Page_Id_Array defines a public database type used by this package.
   type Page_Id_Array is array (Natural range <>) of Page_Id_Type;

   --  Free_List stores the public fields for this database abstraction.
   type Free_List is record
      Count : Natural range 0 .. Max_Free_Pages := 0;
      Pages : Page_Id_Array (1 .. Max_Free_Pages) := (others => No_Page);
   end record;

   --  Validation_Status defines a public database type used by this package.
   type Validation_Status is
     (Valid,
      Invalid_Count,
      Contains_No_Page,
      Contains_Duplicate,
      Contains_Reserved_Page,
      Contains_Out_Of_Range_Page,
      Not_Sorted);

   --  Operation_Status defines a public database type used by this package.
   type Operation_Status is
     (Operation_OK,
      Free_List_Full,
      Page_Already_Free,
      Page_Not_Free,
      Invalid_Page_Id,
      Corrupt_Free_List);

   --  Return is sorted unique for the supplied database state or arguments.
   --  @param List list argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Sorted_Unique (List : Free_List) return Boolean
     with
       Global => null,
       Depends => (Is_Sorted_Unique'Result => List);

   --  Return contains for the supplied database state or arguments.
   --  @param List list argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Contains
     (List : Free_List;
      Page : Page_Id_Type) return Boolean
     with
       Global => null,
       Depends => (Contains'Result => (List, Page));

   --  Return validate for the supplied database state or arguments.
   --  @param List list argument supplied to the operation.
   --  @param First_Usable first usable argument supplied to the operation.
   --  @param Page_Count page count argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate
     (List        : Free_List;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type) return Validation_Status
     with
       Global => null,
       Depends => (Validate'Result => (List, First_Usable, Page_Count));

   --  Return free count for the supplied database state or arguments.
   --  @param List list argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Free_Count (List : Free_List) return Natural is
     (List.Count)
     with
       Global => null,
       Depends => (Free_Count'Result => List);

   --  Perform clear for the supplied database state or arguments.
   --  @param List list argument supplied to the operation.
   procedure Clear (List : out Free_List)
     with
       Global => null,
       Depends => (List => null),
       Post => List.Count = 0;

   --  Add Page to List while preserving sorted unique order.
   --  @param List list argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @param First_Usable first usable argument supplied to the operation.
   --  @param Page_Count page count argument supplied to the operation.
   --  @param Status output value populated by the operation.
   procedure Add_Free_Page
     (List         : in out Free_List;
      Page         : Page_Id_Type;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Status       : out Operation_Status)
     with
       Global => null,
       Depends =>
         (List => (List, Page, First_Usable, Page_Count),
          Status => (List, Page, First_Usable, Page_Count));

   --  Remove and return a reusable page from List.
   --  @param List list argument supplied to the operation.
   --  @param First_Usable first usable argument supplied to the operation.
   --  @param Page_Count page count argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @param Status output value populated by the operation.
   procedure Allocate_Free_Page
     (List         : in out Free_List;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Page         : out Page_Id_Type;
      Status       : out Operation_Status)
     with
       Global => null,
       Depends =>
         (List => (List, First_Usable, Page_Count),
          Page => List,
          Status => (List, First_Usable, Page_Count));

   --  Remove Page from List when it is currently free.
   --  @param List list argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @param First_Usable first usable argument supplied to the operation.
   --  @param Page_Count page count argument supplied to the operation.
   --  @param Status output value populated by the operation.
   procedure Remove_Free_Page
     (List         : in out Free_List;
      Page         : Page_Id_Type;
      First_Usable : Page_Id_Type;
      Page_Count   : Page_Id_Type;
      Status       : out Operation_Status)
     with
       Global => null,
       Depends =>
         (List => (List, Page, First_Usable, Page_Count),
          Status => (List, Page, First_Usable, Page_Count));

end Database.Storage.Free_List_Manager;
