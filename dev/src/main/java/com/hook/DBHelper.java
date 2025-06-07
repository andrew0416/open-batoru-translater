package com.hook;

import java.sql.*;
import java.util.HashMap;
import java.util.Map;

public class DBHelper {
    private static final String DB_URL = "jdbc:sqlite:translate.db";

    static {
        try {
            Class.forName("org.sqlite.JDBC");
        } catch (ClassNotFoundException e) {
            // 로깅 제거
        }
    }

    public static Map<String, String> getTranslationByImageSet(String imageSet) {
        Map<String, String> result = new HashMap<>();
        String sql = "SELECT Name, description, status FROM translate WHERE imageSet = ?";

        try (Connection conn = DriverManager.getConnection(DB_URL);
             PreparedStatement pstmt = conn.prepareStatement(sql)) {

            pstmt.setString(1, imageSet);
            ResultSet rs = pstmt.executeQuery();

            if (rs.next()) {
                result.put("Name", rs.getString("Name"));
                result.put("description", rs.getString("description"));
                result.put("status", rs.getString("status"));
                return result;
            }

        } catch (SQLException e) {
            // 로깅 제거
        }

        return null;
    }
}
