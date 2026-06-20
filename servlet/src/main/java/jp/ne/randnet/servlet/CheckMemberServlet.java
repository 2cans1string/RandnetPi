package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.logging.Logger;

public class CheckMemberServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(CheckMemberServlet.class.getName());
    private static final String ACCOUNTS_CONF = "/etc/randnet/accounts.conf";

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {
        handle(req, resp);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {
        handle(req, resp);
    }

    private void handle(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String memberId = req.getParameter("MEMBERID");
        String diskId   = req.getParameter("DISKID");

        if (memberId == null || memberId.isEmpty()) {
            memberId = "GUEST";
        }
        if (diskId == null) {
            diskId = "";
        }

        String idSuf    = lookupIdSuf(memberId);
        String mailAddr = idSuf + "@dd.randnet.ne.jp";

        log.info("CheckMember OK — MEMBERID=" + memberId + " IDSUF=" + idSuf + " DISKID=" + diskId);

        StringBuilder sb = new StringBuilder();
        sb.append("RESULT=OK\r\n");
        sb.append("RC=0\r\n");
        sb.append("MEMBERID=").append(memberId).append("\r\n");
        sb.append("IDSUF=").append(idSuf).append("\r\n");
        sb.append("MAILADDR=").append(mailAddr).append("\r\n");
        sb.append("DISKID=").append(diskId).append("\r\n");

        byte[] body = sb.toString().getBytes("Shift_JIS");
        resp.setContentType("text/plain");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(body.length);
        resp.getOutputStream().write(body);
    }

    // Returns IDSUF for the given memberId by scanning accounts.conf.
    // Falls back to memberId.toLowerCase() if the file is absent or has no matching entry.
    private String lookupIdSuf(String memberId) {
        File conf = new File(ACCOUNTS_CONF);
        if (!conf.exists()) {
            return memberId.toLowerCase();
        }
        try (BufferedReader br = new BufferedReader(new FileReader(conf))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) {
                    continue;
                }
                // Format: MEMBERID:MEMBERPW:DISKID:IDSUF
                String[] parts = line.split(":", -1);
                if (parts.length >= 4 && parts[0].equalsIgnoreCase(memberId)) {
                    String idSuf = parts[3].trim();
                    if (!idSuf.isEmpty()) {
                        log.info("CheckMember: IDSUF for " + memberId + " loaded from accounts.conf: " + idSuf);
                        return idSuf;
                    }
                }
            }
        } catch (IOException e) {
            log.warning("CheckMember: could not read " + ACCOUNTS_CONF + " — " + e.getMessage());
        }
        return memberId.toLowerCase();
    }
}
