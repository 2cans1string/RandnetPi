package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.logging.Logger;

public class UseMailServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(UseMailServlet.class.getName());

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
        String mailAddr = req.getParameter("MAILADDR");
        log.info("UseMail request — MEMBERID=" + memberId + " MAILADDR=" + mailAddr);

        StringBuilder sb = new StringBuilder();
        sb.append("RESULT=OK\r\n");
        sb.append("RC=0\r\n");
        sb.append("VER=1.00\r\n");

        byte[] body = sb.toString().getBytes("Shift_JIS");
        resp.setContentType("text/plain");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(body.length);
        resp.getOutputStream().write(body);
    }
}
