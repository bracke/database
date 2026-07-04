--  In-process many-readers/single-writer lock used by transactions.
package Database.Locking is
   pragma Elaborate_Body;
   --  In-process read/write lock used by transaction isolation.
   subtype Read_Write_Lock is Database.Read_Write_Lock;
end Database.Locking;
