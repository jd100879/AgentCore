import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

public class ResourceLifecycle {
    public void tidy(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
             CallableStatement call = conn.prepareCall("{ call bump_score(?) }");
             ResultSet rs = stmt.executeQuery("SELECT NOW()")) {
            ps.setInt(1, 42);
            stmt.execute("UPDATE stats SET seen = seen + 1");
            call.setInt(1, 1);
            call.execute();
            if (rs.next()) {
                System.out.println(rs.getString(1));
            }
        }
    }
}
