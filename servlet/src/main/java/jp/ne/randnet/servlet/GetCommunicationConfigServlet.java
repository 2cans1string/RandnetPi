package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.logging.Logger;

/*
 * This servlet is under active investigation. The correct response fields and values
 * required to write the network configuration block to the 64DD disk are known but
 * cannot be safely tested without a disk restoration tool. Not implemented.
 */
public class GetCommunicationConfigServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(GetCommunicationConfigServlet.class.getName());

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
        log.warning("GetCommunicationConfig called — not implemented");

        StringBuilder sb = new StringBuilder();
        sb.append("RESULT=NG\r\n");
        sb.append("RC=9999\r\n");

        byte[] body = sb.toString().getBytes("Shift_JIS");
        resp.setContentType("text/plain");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(body.length);
        resp.getOutputStream().write(body);
    }
}
