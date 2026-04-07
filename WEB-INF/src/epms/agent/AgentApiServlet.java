package epms.agent;

import javax.servlet.RequestDispatcher;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

public class AgentApiServlet extends HttpServlet {
    private static final String RUNTIME_JSP = "/WEB-INF/jspf/agent_runtime.jsp";

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        forward(req, resp);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        forward(req, resp);
    }

    private void forward(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        if (!AgentApiRequestSupport.prepare(req, resp, getServletContext())) {
            return;
        }
        RequestDispatcher dispatcher = req.getRequestDispatcher(RUNTIME_JSP);
        dispatcher.forward(req, resp);
    }
}
