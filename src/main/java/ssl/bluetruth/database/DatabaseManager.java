package ssl.bluetruth.database;

import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;
import javax.sql.DataSource;
import org.apache.log4j.LogManager;
import org.apache.log4j.Logger;

public class DatabaseManager implements DatabaseManagerInterface {

    private static final Logger LOGGER = LogManager.getLogger(DatabaseManager.class);
    private static DatabaseManager instance = null;
    private DataSource dataSource = null;
    private String JDBC_CONNECTION = "java:/comp/env/jdbc/bluetruth";

    /**
     * Method returns singleton instance of this class
     * @return  DatabaseManager instance
     * @throws ssl.bluetruth.database.DatabaseManagerException database manager exception
     */
    public static synchronized DatabaseManager getInstance() throws DatabaseManagerException {
        if (instance == null) {
            instance = new DatabaseManager();
        }
        return instance;
    }

    /**
     * Method destroys singleton instance of this class
     */
    public static void destroy() {
        if (instance != null) {
            synchronized (DatabaseManager.class) {
                instance.dataSource = null;
                instance = null;
            }
        }
    }

    /**
     * Constructor
     * @throws com.ssl.bluetruth.database.DatabaseManagerException
     */
    private DatabaseManager() throws DatabaseManagerException {
        try {
            init();
            LOGGER.info("DatabaseManager object instantiated.");
        } catch (DatabaseManagerException dme) {
            LOGGER.fatal("Could not initialise DatabaseManager");
            destroy();
            throw new DatabaseManagerException("Could not initialise DatabaseManager (" + dme.getMessage() + ")");
        }
    }

    /**
     * Method attempt to establish a connectio with the derby database
     * @throws com.ssl.bluetruth.database.DatabaseManagerException
     */
    private void connectToDatabase() throws DatabaseManagerException {
        try {
            Context context = new InitialContext();
            dataSource = (DataSource) context.lookup(JDBC_CONNECTION);
        } catch (NamingException e) {
            //SCJS005 - logging changes
            LOGGER.fatal("Data source cannot be found (" + e + ")");
            throw new DatabaseManagerException("Failed to resolve database naming ("
                    + e + ")");
        }
        LOGGER.info("Database connection successful");
    }

    /**
     * Initialises database connection
     */
    private void init() throws DatabaseManagerException {
        try {
            connectToDatabase();
        } catch (DatabaseManagerException dme) {
            LOGGER.fatal("Unable to connect to database");
            throw new DatabaseManagerException("Unable to connect to database (" + dme.getMessage() + ")");
        }
    }

    @Override
    public DataSource getDatasource() throws NamingException {
        return dataSource;
    }
}
