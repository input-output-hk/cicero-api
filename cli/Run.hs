{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE LambdaCase #-}
module Run where

import IOHK.Cicero.API.Fact hiding (API)
import IOHK.Cicero.API.Run
import Data.UUID
import Numeric.Natural
import Servant.Client
import Data.Aeson
import System.IO (stdout)
import Data.ByteString.Lazy.Char8
import Control.Exception
import Options.Applicative

import qualified Fact

data GetRunsArgs = GetRunsArgs
  { recursive :: !Bool
  , inputs :: ![ FactID ]
  , offset :: !(Maybe Natural)
  , limit :: !(Maybe Natural)
  }

getRunsArgsParser :: Parser GetRunsArgs
getRunsArgsParser = GetRunsArgs
  <$> switch
        ( long "recursive"
       <> help "get the transitive closure of runs started by facts at FACT_IDs"
        )
  <*> many (option (maybeReader factIdFromString)
             ( long "fact-id"
            <> metavar "FACT_ID"
            <> help "only get runs started by this fact (multiple instances are ANDed together)"
             ))
  <*> optional (option auto
        ( long "offset"
       <> metavar "OFFSET"
       <> help "offset into result list to start query (for pagination)"
        ))
  <*> optional (option auto
        ( long "limit"
       <> metavar "OFFSET"
       <> help "offset into result list to start query (for pagination)"
        ))

getRunsInfo :: ParserInfo GetRunsArgs
getRunsInfo = info getRunsArgsParser
  ( fullDesc
 <> header "cicero-cli run get-all — Get information about runs"
  )

data CreateFactArgs = CreateFactArgs
  { run :: !RunID
  , factArgs :: !Fact.CreateFactArgs
  }

runIdArgsParser :: Parser RunID
runIdArgsParser = option (maybeReader runIdFromString)
  ( long "run-id"
 <> metavar "RUN_ID"
 <> help "the ID of the run to associate the fact with"
  )

createFactArgsParser :: Parser CreateFactArgs
createFactArgsParser = CreateFactArgs
  <$> runIdArgsParser
  <*> Fact.createFactArgsParser

createFactInfo :: ParserInfo CreateFactArgs
createFactInfo = info createFactArgsParser
  ( fullDesc
 <> header "cicero-cli run create-fact — Create a new fact associated with a run"
  )

getLogsInfo :: ParserInfo RunID
getLogsInfo = info runIdArgsParser
  ( fullDesc
 <> header "cicero-cli run get-logs — Get logs for a run"
  )

abortRunInfo :: ParserInfo RunID
abortRunInfo = info runIdArgsParser
  ( fullDesc
 <> header "cicero-cli run abort — Abort a run"
  )

data RunCommand
  = CmdGetRuns !GetRunsArgs
  | CmdCreateFact !CreateFactArgs
  | CmdGetLogs !RunID
  | CmdAbortRun !RunID

runCommandParser :: Parser RunCommand
runCommandParser = hsubparser
  ( command "get-all" (CmdGetRuns <$> getRunsInfo)
 <> command "create-fact" (CmdCreateFact <$> createFactInfo)
 <> command "get-logs" (CmdGetLogs <$> getLogsInfo)
 <> command "abort" (CmdAbortRun <$> abortRunInfo)
  )

runCommandInfo :: ParserInfo RunCommand
runCommandInfo = info runCommandParser
  ( fullDesc
 <> header "cicero-cli run — Manage Cicero runs"
  )

handler :: RunCommand -> Client ClientM API -> ClientEnv -> IO ()
handler (CmdGetRuns gra) runClient cEnv = runClientM (runClient.getAll gra.recursive gra.inputs gra.offset gra.limit) cEnv >>= \case
  Left e -> throw e
  Right res -> hPutStrLn stdout $ encode res
handler (CmdCreateFact createArgs) runClient cEnv =
  Fact.createFactHandler createArgs.factArgs (runClient.createFact createArgs.run) cEnv
handler (CmdGetLogs rid) runClient cEnv = runClientM (runClient.getLogs rid) cEnv >>= \case
  Left e -> throw e
  Right res -> hPutStrLn stdout $ encode res
handler (CmdAbortRun rid) runClient cEnv = runClientM (runClient.abort rid) cEnv >>= \case
  Left e -> throw e
  Right _ -> pure ()
