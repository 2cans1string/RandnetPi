package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.logging.Logger;

public class GetNewVersionServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(GetNewVersionServlet.class.getName());

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
        log.info("GetNewVersion request");

        StringBuilder sb = new StringBuilder();
        sb.append("RESULT=OK\r\n");
        sb.append("RC=0\r\n");
        sb.append("NEWVERSION=0\r\n");

        byte[] body = sb.toString().getBytes("Shift_JIS");
        resp.setContentType("text/plain");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(body.length);
        resp.getOutputStream().write(body);
    }
}
