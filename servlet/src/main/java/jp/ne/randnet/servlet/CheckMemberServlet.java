package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Logger;

public class CheckMemberServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(CheckMemberServlet.class.getName());
    private static final String ACCOUNTS_FILE = "/etc/randnet/accounts.conf";

    private static class Account {
        final String memberId;
        final String memberPw;
        final String diskId;
        final String idSuf;

        Account(String memberId, String memberPw, String diskId, String idSuf) {
            this.memberId = memberId;
            this.memberPw = memberPw;
            this.diskId   = diskId;
            this.idSuf    = idSuf;
        }
    }

    private final List<Account> accounts = new ArrayList<>();

    @Override
    public void init() throws ServletException {
        loadAccounts();
    }

    private void loadAccounts() {
        accounts.clear();
        File f = new File(ACCOUNTS_FILE);
        if (!f.exists()) {
            log.warning("Accounts file not found: " + ACCOUNTS_FILE);
            return;
        }
        try (BufferedReader br = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] parts = line.split(":");
                if (parts.length < 4) continue;
                accounts.add(new Account(
                    parts[0].trim(), parts[1].trim(),
                    parts[2].trim(), parts[3].trim()
                ));
            }
        } catch (IOException e) {
            log.severe("Failed to load accounts: " + e.getMessage());
        }
        log.info("Loaded " + accounts.size() + " account(s) from " + ACCOUNTS_FILE);
    }

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
        String memberPw = req.getParameter("MEMBERPW");
        String diskId   = req.getParameter("DISKID");

        log.info("CheckMember request — MEMBERID=" + memberId + " DISKID=" + diskId);

        Account match = null;
        for (Account a : accounts) {
            if (a.memberId.equals(memberId)
                    && a.memberPw.equals(memberPw)
                    && a.diskId.equals(diskId)) {
                match = a;
                break;
            }
        }

        StringBuilder sb = new StringBuilder();
        if (match != null) {
            String mailAddr = match.idSuf + "@dd.randnet.ne.jp";
            sb.append("RESULT=OK\r\n");
            sb.append("RC=0\r\n");
            sb.append("MEMBERID=").append(match.memberId).append("\r\n");
            sb.append("IDSUF=").append(match.idSuf).append("\r\n");
            sb.append("MAILADDR=").append(mailAddr).append("\r\n");
            sb.append("DISKID=").append(match.diskId).append("\r\n");
            log.info("CheckMember OK — MEMBERID=" + match.memberId);
        } else {
            sb.append("RESULT=NG\r\n");
            sb.append("RC=1001\r\n");
            log.warning("CheckMember FAILED — MEMBERID=" + memberId + " DISKID=" + diskId);
        }

        byte[] body = sb.toString().getBytes("Shift_JIS");
        resp.setContentType("text/plain");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(body.length);
        resp.getOutputStream().write(body);
    }
}
