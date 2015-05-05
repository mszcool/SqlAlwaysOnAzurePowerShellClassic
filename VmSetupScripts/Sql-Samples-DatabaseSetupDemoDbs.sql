USE master
GO
CREATE DATABASE [SqlDemoDb1]
GO
CREATE DATABASE [SqlDemoDb2]
GO
USE SqlDemoDb1
GO
CREATE TABLE [TestTable]
(
  MyId INT PRIMARY KEY,
  MyText nvarchar(max) NOT NULL
)
GO
USE SqlDemoDb2
GO
CREATE TABLE [TestTable2]
(
  SecId INT PRIMARY KEY,
  SecText nvarchar(max) NOT NULL
)
GO
USE master
GO