package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.logging.Logger;

public class CheckMemberServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(CheckMemberServlet.class.getName());

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

        log.info("CheckMember OK (open) — MEMBERID=" + memberId + " DISKID=" + diskId);

        String idSuf    = memberId.toLowerCase();
        String mailAddr = idSuf + "@dd.randnet.ne.jp";

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
}
