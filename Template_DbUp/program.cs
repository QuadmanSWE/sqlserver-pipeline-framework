using DbUp;
using DbUp.Helpers;
using System;
using System.Configuration;
using System.Reflection;

namespace Template_DbUp
{
    class Program
    {
        static void Main(string[] args)
        {
            string connectionString;
            if (args.Length > 0)
            {
                connectionString = args[0];
            }
            else
            {
#if DEBUG
                connectionString = ConfigurationManager.ConnectionStrings["Local"].ConnectionString;
#else
                throw new ConfigurationErrorsException("Missing connectionstring argument when calling DbUp");
#endif
            }
            Console.WriteLine(String.Format("Deploying using connectionstring: [{0}]", connectionString));
            var schemaMigrationRunner = DeployChanges
                .To
                .SqlDatabase(connectionString)
                .WithScriptsEmbeddedInAssembly(
                    Assembly.GetExecutingAssembly(),
                    s => s.Contains("SchemaMigration"))
                .LogToConsole()
                .Build();

            schemaMigrationRunner.PerformUpgrade();

            var idempotentRunner = DeployChanges.To
              .SqlDatabase(connectionString)
              .WithScriptsEmbeddedInAssembly(
                  Assembly.GetExecutingAssembly(),
                  s => s.Contains("Idempotent"))
              .JournalTo(new NullJournal())
              .LogToConsole()
              .Build();
            idempotentRunner.PerformUpgrade();
        }
    }
}
