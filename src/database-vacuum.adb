with Ada.Containers;
with Database.Catalog;
with Database.Full_Text;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.Table_Heap;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body Database.Vacuum is
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;

   function Row_Value_For_Column
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Column : Natural) return Database.Values.Value
   is
      Pos : constant Natural :=
        Database.Schema.Find_Column_Id_Position (Schema, Column);
   begin
      if Pos = Natural'Last then
         return Database.Values.Null_Value;
      end if;
      return Database.Rows.Get (Row, Pos);
   exception
      when others =>
         return Database.Values.Null_Value;
   end Row_Value_For_Column;

   function Remove_Reclaimed_Index_Refs
     (Tx        : in out Database.Transactions.Transaction;
      DB        : access Database.Handle;
      Schema    : Database.Schema.Table_Schema;
      Reclaimed : Database.Storage.Table_Heap.Reclaimed_Row_Vectors.Vector)
      return Database.Status.Result
   is
      R : Database.Status.Result;
      Primary_Pos : constant Natural := Database.Schema.Primary_Key_Index (Schema);
   begin
      if Reclaimed.Length = 0 then
         return Database.Status.Success;
      end if;

      for Reclaimed_Row of Reclaimed loop
         if Schema.Primary_Index_Root /= 0 and then Primary_Pos /= Natural'Last then
            declare
               Key : constant Database.Values.Value :=
                 Database.Rows.Get (Reclaimed_Row.Row, Primary_Pos);
            begin
               if Key.Kind /= Database.Types.Null_Value then
                  R := Database.Indexes.BTree.Remove_Entry
                    (Tx, DB.File,
                     Database.Storage.Pages.Page_Id (Schema.Primary_Index_Root),
                     Key, Reclaimed_Row.Ref);
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
               end if;
            exception
               when others =>
                  null;
            end;
         end if;

         for IX of Schema.Indexes loop
            if IX.Root_Page /= Database.Storage.Pages.Invalid_Page_Id then
               declare
                  Key : constant Database.Values.Value :=
                    Row_Value_For_Column (Schema, Reclaimed_Row.Row, IX.Column_Id);
               begin
                  if Key.Kind /= Database.Types.Null_Value then
                     R := Database.Indexes.BTree.Remove_Entry
                       (Tx, DB.File, IX.Root_Page, Key, Reclaimed_Row.Ref);
                     if not Database.Status.Is_Ok (R) then
                        return R;
                     end if;
                  end if;
               end;
            end if;
         end loop;
      end loop;

      return Database.Status.Success;
   end Remove_Reclaimed_Index_Refs;

   function Vacuum
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result
   is
      DB        : constant access Database.Handle := Database.Transactions.Owning_Database (Tx);
      R         : Database.Status.Result;
      Reclaimed : Natural;
      Reclaimed_Rows : Database.Storage.Table_Heap.Reclaimed_Row_Vectors.Vector;
   begin
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "vacuum requires a read-write transaction");
      end if;
      if DB = null then
         return Database.Status.Failure
           (Database.Status.Transaction_Error,
            "vacuum requires an active transaction");
      end if;

      Database.Full_Text.Select_Database (Database.Full_Text_State_Key (DB.all));
      Database.Full_Text.Vacuum_All;

      if Database.Backend (DB.all) = Database.Persistent_Backend then
         Database.Catalog.Select_Database (Database.Catalog_State_Key (DB.all));
         for I in 0 .. Database.Catalog.Table_Count - 1 loop
            declare
               S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (I);
            begin
               if S.Heap_First_Page /= 0 then
                  R := Database.Storage.Table_Heap.Vacuum_Deleted
                    (Tx,
                     DB.File,
                     Database.Storage.Pages.Page_Id (S.Heap_First_Page),
                     S,
                     Reclaimed,
                     Reclaimed_Rows);
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
                  R := Remove_Reclaimed_Index_Refs (Tx, DB, S, Reclaimed_Rows);
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
               end if;
            end;
         end loop;
      end if;

      return Database.Status.Success;
   end Vacuum;

end Database.Vacuum;
