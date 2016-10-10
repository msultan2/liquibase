/**
 *  @(#) DatabaseManagerException.java
 *
 *
 * THIS SOFTWARE IS PROVIDED BY SIMULATION SYSTEMS LTD ``AS IS'' AND
 * ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL SIMULATION
 * SYSTEMS LTD BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
 * USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * Copyright 2009 (C) Simulation Systems Ltd. All Rights Reserved.
 *
 * Java version: JDK 1.6
 *
 * Created By: KGB
 *
 * Product: 403
 *
 * Change History: Created on February 09, 2009, 11:50 AM Version 001
 */

package ssl.bluetruth.database;

/**
 * Exception class for the DatabaseManager
 * @author kbennett
 */
public class DatabaseManagerException extends Exception {
    /**
     * Constructor
     * @param message   exception message
     */
    public DatabaseManagerException(String message) {
        super(message);
    }
}
