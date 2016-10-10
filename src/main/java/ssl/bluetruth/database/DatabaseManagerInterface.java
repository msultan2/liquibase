/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package ssl.bluetruth.database;

import javax.naming.NamingException;
import javax.sql.DataSource;

/**
 *
 * @author xzhang
 */
public interface DatabaseManagerInterface {

    DataSource getDatasource() throws NamingException;
    
}
